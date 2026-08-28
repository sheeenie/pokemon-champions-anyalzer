import { ImageHasher } from './hasher.js';

/**
 * Pokémon Matching Module
 */
export class PokemonMatcher {
  constructor() {
    this.database = [];
    this.customHashes = this.loadCustomHashes();
    this.cache = new Map();
    this.reusableCanvas = document.createElement('canvas');
  }

  loadCustomHashes() {
    try {
      const saved = localStorage.getItem('pca_custom_hashes');
      if (saved) return JSON.parse(saved);
    } catch (e) {
      console.warn('Failed to load custom hashes', e);
    }
    return { player: {}, opponent: {} };
  }

  saveCustomHashes() {
    try {
      localStorage.setItem('pca_custom_hashes', JSON.stringify(this.customHashes));
    } catch (e) {
      console.warn('Failed to save custom hashes', e);
    }
  }

  /**
   * Learn a Pokémon's visual fingerprint from a user's exact screen crop
   * @param {HTMLCanvasElement} canvas 
   * @param {string} slotType 'player' or 'opponent'
   * @param {string} pokemonName 
   */
  learnPokemon(canvas, slotType, pokemonName) {
    const hash = ImageHasher.computeDHash(canvas, this.reusableCanvas);
    const histogram = ImageHasher.computeColorHistogram(canvas, this.reusableCanvas);
    
    if (!this.customHashes[slotType][pokemonName]) {
      this.customHashes[slotType][pokemonName] = [];
    }
    
    // Store multiple variations if needed, but 1 is usually enough
    this.customHashes[slotType][pokemonName].push({ hash, histogram });
    this.saveCustomHashes();
    console.log(`[Matcher] Learned custom hash for ${pokemonName} (${slotType})`);
  }

  /**
   * Load sprite database
   * @param {string} url URL to sprites-db.json
   */
  async loadDatabase(url) {
    const response = await fetch(url);
    const data = await response.json();
    this.database = data.pokemon || [];
  }

  /**
   * Identify a Pokemon from a cropped canvas
   * @param {HTMLCanvasElement} croppedCanvas 
   * @param {string} slotType 'player' or 'opponent'
   * @returns {Object|null} Match result
   */
  identifyPokemon(croppedCanvas, slotType) {
    if (this.database.length === 0) return null;

    const inputHash = ImageHasher.computeDHash(croppedCanvas, this.reusableCanvas);
    const inputHist = ImageHasher.computeColorHistogram(croppedCanvas, this.reusableCanvas);
    let candidates = [];

    // 1. Check custom learned hashes FIRST (highest priority because they are exact screen crops)
    for (const [name, variations] of Object.entries(this.customHashes[slotType])) {
      for (const custom of variations) {
        const distance = ImageHasher.hammingDistance(inputHash, custom.hash);
        if (distance <= 10) {
          const entry = this.database.find(p => p.name === name);
          if (entry) {
            return {
              id: entry.id,
              name: entry.name,
              confidence: 1.0, // High confidence since it's a learned crop
              sprite: entry.sprite
            };
          }
        }
      }
    }

    // 2. Check offline fallback database
    for (const entry of this.database) {
      const dbHash = slotType === 'player' ? entry.playerHash : entry.opponentHash;
      const distance = ImageHasher.hammingDistance(inputHash, dbHash);
      if (distance <= 15) {
        candidates.push({ entry, distance });
      }
    }

    if (candidates.length === 0) return null;

    if (candidates.length === 1) {
      const { entry, distance } = candidates[0];
      return {
        id: entry.id,
        name: entry.name,
        confidence: 1 - (distance / 64),
        sprite: entry.sprite
      };
    }

    // Multiple candidates, use color histogram
    let bestMatch = null;
    let bestScore = -1;
    let bestDistance = 0;

    for (const { entry, distance } of candidates) {
      const dbHist = slotType === 'player' ? entry.playerHistogram : entry.opponentHistogram;
      const score = ImageHasher.histogramIntersection(inputHist, dbHist);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = entry;
        bestDistance = distance;
      }
    }

    return {
      id: bestMatch.id,
      name: bestMatch.name,
      confidence: bestScore * (1 - (bestDistance / 64)),
      sprite: bestMatch.sprite
    };
  }

  /**
   * Identify all Pokemon from an array of cropped canvases, using cache
   * @param {Array<HTMLCanvasElement>} croppedCanvases 
   * @returns {Array<Object|null>} Array of results
   */
  identifyAll(croppedCanvases) {
    return croppedCanvases.map((canvas, index) => {
      if (!canvas) return null;
      
      const slotType = index < 2 ? 'opponent' : 'player';
      const hash = ImageHasher.computeDHash(canvas, this.reusableCanvas);
      
      if (this.cache.has(index)) {
        const cached = this.cache.get(index);
        const distance = ImageHasher.hammingDistance(hash, cached.hash);
        if (distance <= 5) {
          return cached.result;
        }
      }

      const result = this.identifyPokemon(canvas, slotType);
      
      // Only cache if we actually found something
      if (result) {
        this.cache.set(index, { hash, result });
      } else {
        this.cache.delete(index);
      }
      
      return result;
    });
  }
}
