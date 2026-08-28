#!/usr/bin/env node

/**
 * Build Sprite Database (Offline Compositing Edition)
 * 
 * Fetches menu sprites from Bulbagarden Archives.
 * Automatically resolves Pokémon names using PokéAPI.
 * Composites transparent sprites onto the exact game UI background gradients 
 * (Player = Blue, Opponent = Red/Purple).
 * Generates dual hashes/histograms for 100% offline accurate matching.
 * 
 * Usage: node scripts/build-sprite-db.js
 */

import { createCanvas, loadImage } from '@napi-rs/canvas';
import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '..');
const OUTPUT_DIR = join(PROJECT_ROOT, 'public');
const SPRITES_DIR = join(OUTPUT_DIR, 'sprites');

const WIKI_API = 'https://archives.bulbagarden.net/w/api.php?action=query&generator=categorymembers&gcmtitle=Category:Champions_menu_sprites&gcmlimit=500&prop=imageinfo&iiprop=url&format=json';
const POKE_API = 'https://pokeapi.co/api/v2/pokemon?limit=1500';

/**
 * Compute dHash (difference hash) of an image
 */
function computeDHash(canvas) {
  const hashCanvas = createCanvas(9, 8);
  const ctx = hashCanvas.getContext('2d');
  ctx.drawImage(canvas, 0, 0, 9, 8);
  const { data } = ctx.getImageData(0, 0, 9, 8);

  const gray = new Float32Array(72);
  for (let i = 0; i < 72; i++) {
    const idx = i * 4;
    gray[i] = 0.299 * data[idx] + 0.587 * data[idx + 1] + 0.114 * data[idx + 2];
  }

  let hashBits = '';
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const left = gray[row * 9 + col];
      const right = gray[row * 9 + col + 1];
      hashBits += left > right ? '1' : '0';
    }
  }

  let hex = '';
  for (let i = 0; i < 64; i += 4) {
    hex += parseInt(hashBits.substring(i, i + 4), 2).toString(16);
  }
  return hex;
}

/**
 * Compute HSV color histogram (8x8x4 = 256 bins)
 */
function computeColorHistogram(canvas) {
  const histCanvas = createCanvas(64, 64);
  const ctx = histCanvas.getContext('2d');
  ctx.drawImage(canvas, 0, 0, 64, 64);
  const { data } = ctx.getImageData(0, 0, 64, 64);

  const bins = new Float32Array(256);
  let totalPixels = 0;

  for (let i = 0; i < data.length; i += 4) {
    const r = data[i] / 255;
    const g = data[i + 1] / 255;
    const b = data[i + 2] / 255;

    totalPixels++;

    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const delta = max - min;

    let h = 0, s = 0, v = max;

    if (delta > 0) {
      s = delta / max;
      if (max === r) h = ((g - b) / delta) % 6;
      else if (max === g) h = (b - r) / delta + 2;
      else h = (r - g) / delta + 4;
      h *= 60;
      if (h < 0) h += 360;
    }

    const hBin = Math.min(7, Math.floor(h / 45));
    const sBin = Math.min(7, Math.floor(s * 8));
    const vBin = Math.min(3, Math.floor(v * 4));

    const binIndex = hBin * 32 + sBin * 4 + vBin;
    bins[binIndex]++;
  }

  if (totalPixels > 0) {
    for (let i = 0; i < bins.length; i++) {
      bins[i] /= totalPixels;
    }
  }

  return Array.from(bins).map(v => Math.round(v * 10000) / 10000);
}

/**
 * Apply a background gradient to the image
 */
function applyBackground(img, type) {
  const size = 128;
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');
  
  const grad = ctx.createLinearGradient(0, 0, size, size);
  if (type === 'player') {
    grad.addColorStop(0, '#3B62C8');
    grad.addColorStop(1, '#1A2A6C');
  } else {
    grad.addColorStop(0, '#C83F4C');
    grad.addColorStop(1, '#4F3074');
  }
  
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);
  ctx.drawImage(img, 0, 0, size, size);
  return canvas;
}

function saveThumbnail(img, filename) {
  const size = 96;
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, size, size);
  const buffer = canvas.toBuffer('image/png');
  writeFileSync(join(SPRITES_DIR, filename), buffer);
}

async function fetchPokeAPIDex() {
  console.log('Fetching base names from PokéAPI...');
  const res = await fetch(POKE_API);
  const data = await res.json();
  const dexMap = {};
  for (const entry of data.results) {
    // Extract ID from URL (e.g. https://pokeapi.co/api/v2/pokemon/3/)
    const idMatch = entry.url.match(/\/(\d+)\/$/);
    if (idMatch) {
      dexMap[parseInt(idMatch[1], 10)] = entry.name;
    }
  }
  return dexMap;
}

async function build() {
  console.log('🔨 Building Pokémon sprite database from Bulbagarden (Compositing Mode)...');

  if (!existsSync(SPRITES_DIR)) {
    mkdirSync(SPRITES_DIR, { recursive: true });
  }

  const dexMap = await fetchPokeAPIDex();

  console.log('Fetching image URLs from MediaWiki API...');
  const res = await fetch(WIKI_API);
  const data = await res.json();
  const pages = Object.values(data.query.pages);
  
  const db = [];
  const errors = [];
  let processed = 0;

  const targetImages = [];
  
  for (const page of pages) {
    if (!page.imageinfo || !page.imageinfo[0]) continue;
    const title = page.title;
    const url = page.imageinfo[0].url;
    
    // Parse "File:Menu CP 0006-Mega X.png"
    const match = title.match(/Menu CP (\d{4})(?:-(.+))?\.png/);
    if (!match) continue;
    
    const num = parseInt(match[1], 10);
    const formStr = match[2] ? match[2].toLowerCase().replace(/ /g, '-') : '';
    
    const baseName = dexMap[num];
    if (!baseName) {
      errors.push(`Could not find base name for ID ${num}`);
      continue;
    }
    
    let name = baseName;
    let isMega = false;
    
    if (formStr) {
      if (formStr.includes('mega')) {
        isMega = true;
      }
      // e.g. charizard + -mega-x = charizard-mega-x
      name = `${baseName}-${formStr}`;
    }
    
    targetImages.push({ id: num, name, isMega, url });
  }

  console.log(`Found ${targetImages.length} sprites. Downloading and compositing...`);

  // Download and process
  for (const target of targetImages) {
    const { id, name, isMega, url } = target;
    try {
      const res = await fetch(url, {
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const buf = Buffer.from(await res.arrayBuffer());
      const img = await loadImage(buf);
      
      // Composite Player version
      const playerCanvas = applyBackground(img, 'player');
      const playerHash = computeDHash(playerCanvas);
      const playerHistogram = computeColorHistogram(playerCanvas);
      
      // Composite Opponent version
      const opponentCanvas = applyBackground(img, 'opponent');
      const opponentHash = computeDHash(opponentCanvas);
      const opponentHistogram = computeColorHistogram(opponentCanvas);
      
      const thumbFilename = `${name}.png`;
      saveThumbnail(img, thumbFilename); // Save the transparent version for UI display
      
      db.push({
        id,
        name,
        mega: isMega,
        sprite: `/sprites/${thumbFilename}`,
        playerHash,
        playerHistogram,
        opponentHash,
        opponentHistogram
      });
      
      processed++;
      const pct = Math.round((processed / targetImages.length) * 100);
      process.stdout.write(`\r  Progress: ${processed}/${targetImages.length} (${pct}%)`);
    } catch (e) {
      errors.push(`${name}: ${e.message}`);
    }
  }

  console.log('\n');

  const dbPath = join(OUTPUT_DIR, 'sprites-db.json');
  writeFileSync(dbPath, JSON.stringify({ 
    version: 3, // Version 3 -> Composited dual hashes
    generated: new Date().toISOString(),
    count: db.length,
    pokemon: db 
  }, null, 2));

  console.log('✅ Build complete!');
  console.log(`   Sprites generated: ${db.length}`);
  if (errors.length > 0) {
    console.log(`   Errors: ${errors.length}`);
    console.log(errors.slice(0, 5).join('\n'));
  }
}

build().catch(console.error);
