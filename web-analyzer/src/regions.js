/**
 * Sprite Region Management
 */
export class RegionManager {
  constructor() {
    this.defaultRegions = {
      OPPONENT_SLOT_1: { x: 0.56, y: 0.02, w: 0.05, h: 0.08 },
      OPPONENT_SLOT_2: { x: 0.72, y: 0.02, w: 0.05, h: 0.08 },
      PLAYER_SLOT_1: { x: 0.02, y: 0.82, w: 0.05, h: 0.08 },
      PLAYER_SLOT_2: { x: 0.12, y: 0.82, w: 0.05, h: 0.08 }
    };
    
    this.regions = {};
    this.loadRegions();
  }

  /**
   * Get regions converted to pixel coordinates based on dimensions
   * @param {number} videoWidth 
   * @param {number} videoHeight 
   * @returns {Object}
   */
  getRegions(videoWidth, videoHeight) {
    const pixelRegions = {};
    for (const [name, rect] of Object.entries(this.regions)) {
      pixelRegions[name] = {
        x: Math.round(rect.x * videoWidth),
        y: Math.round(rect.y * videoHeight),
        w: Math.round(rect.w * videoWidth),
        h: Math.round(rect.h * videoHeight)
      };
    }
    return pixelRegions;
  }

  /**
   * Crop a specific region from the source canvas
   * @param {HTMLCanvasElement} sourceCanvas 
   * @param {Object} region Pixel coordinates {x,y,w,h}
   * @returns {HTMLCanvasElement}
   */
  cropRegion(sourceCanvas, region) {
    const canvas = document.createElement('canvas');
    canvas.width = region.w;
    canvas.height = region.h;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(sourceCanvas, region.x, region.y, region.w, region.h, 0, 0, region.w, region.h);
    return canvas;
  }

  /**
   * Crop all predefined regions
   * @param {HTMLCanvasElement} sourceCanvas 
   * @returns {{opponent: HTMLCanvasElement[], player: HTMLCanvasElement[]}}
   */
  cropAllRegions(sourceCanvas) {
    const pixelRegions = this.getRegions(sourceCanvas.width, sourceCanvas.height);
    
    return {
      opponent: [
        this.cropRegion(sourceCanvas, pixelRegions.OPPONENT_SLOT_1),
        this.cropRegion(sourceCanvas, pixelRegions.OPPONENT_SLOT_2)
      ],
      player: [
        this.cropRegion(sourceCanvas, pixelRegions.PLAYER_SLOT_1),
        this.cropRegion(sourceCanvas, pixelRegions.PLAYER_SLOT_2)
      ]
    };
  }

  /**
   * Update a region's percentage coordinates
   * @param {string} slotName 
   * @param {Object} rect {x,y,w,h} in percentages
   */
  setRegion(slotName, rect) {
    this.regions[slotName] = { ...rect };
  }

  /**
   * Save regions to localStorage
   */
  saveRegions() {
    try {
      localStorage.setItem('pokemon_regions', JSON.stringify(this.regions));
    } catch (e) {
      console.warn("Failed to save regions to localStorage", e);
    }
  }

  /**
   * Load regions from localStorage or fallback to defaults
   */
  loadRegions() {
    try {
      const saved = localStorage.getItem('pokemon_regions');
      if (saved) {
        this.regions = JSON.parse(saved);
        return;
      }
    } catch (e) {
      console.warn("Failed to load regions from localStorage", e);
    }
    this.resetToDefaults();
  }

  /**
   * Reset all regions to their default values
   */
  resetToDefaults() {
    this.regions = JSON.parse(JSON.stringify(this.defaultRegions));
    this.saveRegions();
  }
}
