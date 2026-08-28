import { ScreenCapture } from './capture.js';
import { PokemonMatcher } from './matcher.js';
import { RegionManager } from './regions.js';
import { HPReader } from './ocr.js';
import { PokeAPIClient } from './pokeapi.js';
import { BattleAnalyzer } from './battle.js';
import { UIRenderer } from './ui.js';
import { CalibrationManager } from './calibration.js';
import { GeminiClient } from './gemini.js';
import './style.css';

class App {
  constructor() {
    this.capture = new ScreenCapture();
    this.matcher = new PokemonMatcher();
    this.regions = new RegionManager();
    this.hpReader = new HPReader();
    this.api = new PokeAPIClient();
    this.battle = new BattleAnalyzer(this.api);
    this.ui = new UIRenderer();
    this.calibrator = new CalibrationManager(this.regions, this.capture);
    this.gemini = new GeminiClient(this.matcher);
    
    this.isRunning = false;
    this.loopInterval = null;
    this.frameCount = 0;
    this.lastFpsTime = Date.now();
    this.currentPokemon = { player: [null, null], opponent: [null, null] };
    this.isDoubleBattle = true;
  }
  
  async init() {
    // Load sprite database
    await this.matcher.loadDatabase('/sprites-db.json');
    
    // Initialize OCR
    await this.hpReader.init();
    
    // Load saved regions
    this.regions.loadRegions();
    
    // Set up event listeners
    this.setupEventListeners();
    
    // Show welcome modal if first visit
    if (!localStorage.getItem('pca-welcomed')) {
      this.ui.showWelcome();
    }
  }
  
  setupEventListeners() {
    // Capture button
    const btnCapture = document.getElementById('btn-capture');
    if (btnCapture) {
      btnCapture.addEventListener('click', () => this.toggleCapture());
    }
    
    // Calibrate button  
    const btnCalibrate = document.getElementById('btn-calibrate');
    if (btnCalibrate) {
      btnCalibrate.addEventListener('click', () => this.toggleCalibration());
    }
    
    // Welcome modal start button
    const btnWelcomeStart = document.getElementById('btn-welcome-start');
    if (btnWelcomeStart) {
      btnWelcomeStart.addEventListener('click', () => {
        this.ui.hideWelcome();
        localStorage.setItem('pca-welcomed', 'true');
        this.toggleCapture();
      });
    }

    // Battle format toggles
    const btnSingle = document.getElementById('btn-format-single');
    const btnDouble = document.getElementById('btn-format-double');
    if (btnSingle) btnSingle.addEventListener('click', () => this.setFormat(false));
    if (btnDouble) btnDouble.addEventListener('click', () => this.setFormat(true));
    // Calibration save/cancel
    const btnCalSave = document.getElementById('btn-cal-save');
    const btnCalCancel = document.getElementById('btn-cal-cancel');
    if (btnCalSave) btnCalSave.addEventListener('click', () => this.saveCalibration());
    if (btnCalCancel) btnCalCancel.addEventListener('click', () => this.toggleCalibration());
    
    // Settings
    const btnSettings = document.getElementById('btn-settings');
    const modalSettings = document.getElementById('settings-modal');
    const inputApiKey = document.getElementById('gemini-api-key');
    const btnSettingsSave = document.getElementById('btn-settings-save');
    const btnSettingsCancel = document.getElementById('btn-settings-cancel');
    
    if (btnSettings && modalSettings) {
      btnSettings.addEventListener('click', () => {
        if (inputApiKey) inputApiKey.value = this.gemini.apiKey;
        modalSettings.classList.remove('hidden');
      });
      
      btnSettingsCancel.addEventListener('click', () => {
        modalSettings.classList.add('hidden');
      });
      
      btnSettingsSave.addEventListener('click', () => {
        if (inputApiKey) this.gemini.setApiKey(inputApiKey.value.trim());
        modalSettings.classList.add('hidden');
      });
    }
  }
  
  setFormat(isDouble) {
    this.isDoubleBattle = isDouble;
    this.ui.setBattleFormat(isDouble);
    this.calibrator.isDoubleBattle = isDouble;
    // Force re-analysis of current frame if running
    if (this.isRunning) {
      this.currentPokemon = { player: [null, null], opponent: [null, null] };
    }
  }
  
  async toggleCapture() {
    if (this.capture.isActive()) {
      this.stopAnalysis();
    } else {
      await this.startAnalysis();
    }
  }
  
  async startAnalysis() {
    try {
      const stream = await this.capture.startCapture();
      
      // Display video preview
      const video = this.capture.getVideoElement();
      const previewContainer = document.getElementById('video-container');
      if (previewContainer) {
        previewContainer.innerHTML = '';
        previewContainer.appendChild(video);
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.objectFit = 'contain';
        video.style.borderRadius = '12px';
        video.style.display = 'block';
      }
      
      this.ui.setCapturing(true);
      
      // Handle stream ending if tracks exist
      if (stream && stream.getVideoTracks().length > 0) {
        stream.getVideoTracks()[0].addEventListener('ended', () => {
          this.stopAnalysis();
        });
      }
      
      // Start the analysis loop (every 500ms)
      this.isRunning = true;
      this.loopInterval = setInterval(() => this.analysisLoop(), 500);
      
    } catch (err) {
      console.error('Failed to start capture:', err);
      this.ui.updateStatus({ error: 'Failed to start screen capture' });
    }
  }
  
  stopAnalysis() {
    this.isRunning = false;
    if (this.loopInterval) {
      clearInterval(this.loopInterval);
      this.loopInterval = null;
    }
    this.capture.stopCapture();
    this.ui.setCapturing(false);
    this.ui.showPlaceholder();
  }
  
  async analysisLoop() {
    if (!this.isRunning || this.isProcessing) return;
    this.isProcessing = true;
    
    try {
      const frame = this.capture.captureFrame();
      if (!frame) return;
      
      this.frameCount++;
      
      // 1. Crop sprite regions
      const crops = this.regions.cropAllRegions(frame.canvas);
      
      // 2. Identify Pokémon via hash matching
      const allCrops = [...(crops.opponent || []), ...(crops.player || [])];
      let matches = this.matcher.identifyAll(allCrops);
      
      // GEMINI FALLBACK LEARNING
      if (this.gemini.hasApiKey()) {
        for (let i = 0; i < allCrops.length; i++) {
          if (!this.isDoubleBattle && (i === 1 || i === 3)) continue; // Skip slot 2 in singles
          
          if (!matches[i] && allCrops[i]) {
            // Unmatched valid crop -> Send to Gemini
            const slotType = i < 2 ? 'opponent' : 'player';
            console.log(`[Gemini] Attempting to learn unknown Pokémon in ${slotType} slot ${i}...`);
            const name = await this.gemini.identifyPokemon(allCrops[i]);
            if (name) {
              this.matcher.learnPokemon(allCrops[i], slotType, name);
              // Re-run identification for this slot now that we learned it
              matches[i] = this.matcher.identifyPokemon(allCrops[i], slotType);
            }
          }
        }
      }
      
      // 3. Check if any Pokémon changed
      const opponentMatches = matches.slice(0, 2);
      const playerMatches = matches.slice(2, 4);
      
      if (!this.isDoubleBattle) {
        opponentMatches[1] = null;
        playerMatches[1] = null;
      }
      
      let changed = false;
      for (let i = 0; i < (this.isDoubleBattle ? 2 : 1); i++) {
        if (opponentMatches[i]?.name !== this.currentPokemon.opponent[i]?.name) changed = true;
        if (playerMatches[i]?.name !== this.currentPokemon.player[i]?.name) changed = true;
      }
      
      if (changed) {
        // 4. Fetch full data from PokéAPI for new Pokémon
        const playerData = await Promise.all(
          playerMatches.filter(Boolean).map(m => this.api.getPokemon(m.name))
        );
        const opponentData = await Promise.all(
          opponentMatches.filter(Boolean).map(m => this.api.getPokemon(m.name))
        );
        
        // 5. Get type matchups and weaknesses
        for (const p of [...playerData, ...opponentData]) {
          if (p) {
            p.weaknesses = await this.api.getTypeMatchups(p.types);
          }
        }
        
        // 6. Analyze battle
        const analysis = await this.battle.analyzeBattle(playerData, opponentData);
        
        // 7. Update UI
        this.ui.renderPokemonCard('opponent-card-1', opponentData[0]);
        this.ui.renderPokemonCard('opponent-card-2', opponentData[1]);
        this.ui.renderPokemonCard('player-card-1', playerData[0]);
        this.ui.renderPokemonCard('player-card-2', playerData[1]);
        this.ui.renderMatchupMatrix(playerData, opponentData, analysis.matchups);
        this.ui.renderBattleTips(analysis.tips);
        
        // Update current state
        this.currentPokemon.opponent = opponentMatches;
        this.currentPokemon.player = playerMatches;
      }
      
      // Update FPS counter
      const now = Date.now();
      if (now - this.lastFpsTime >= 1000) {
        this.ui.updateStatus({
          fps: this.frameCount,
          matched: matches.filter(Boolean).length,
          total: matches.length,
          cacheSize: this.api.getCacheSize?.() || 0
        });
        this.frameCount = 0;
        this.lastFpsTime = now;
      }
      
    } catch (err) {
      console.error('Analysis loop error:', err);
    } finally {
      this.isProcessing = false;
    }
  }
  
  toggleCalibration() {
    const overlay = document.getElementById('calibration-overlay');
    if (!overlay) return;
    
    if (overlay.classList.contains('hidden')) {
      this.ui.showCalibration();
      this.calibrator.start();
    } else {
      this.ui.hideCalibration();
      this.calibrator.stop();
      // Also restore original regions if cancelled
      this.regions.loadRegions();
    }
  }
  
  saveCalibration() {
    this.regions.saveRegions();
    this.calibrator.stop();
    this.ui.hideCalibration();
  }
}

// Boot the app
document.addEventListener('DOMContentLoaded', () => {
  const app = new App();
  app.init().catch(console.error);
});
