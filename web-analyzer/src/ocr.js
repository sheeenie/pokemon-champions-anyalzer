import { createWorker } from 'tesseract.js';

/**
 * HP Reading Module using OCR
 */
export class HPReader {
  constructor() {
    this.worker = null;
    this.initialized = false;
  }

  /**
   * Initialize Tesseract worker
   */
  async init() {
    if (this.initialized) return;
    
    this.worker = await createWorker('eng', 1, {
      logger: m => {} // Ignore logs to prevent spam
    });
    
    await this.worker.setParameters({
      tessedit_char_whitelist: '0123456789/%',
      tessedit_pageseg_mode: '7' // Treat image as single text line
    });
    
    this.initialized = true;
  }

  /**
   * Read HP from a cropped canvas
   * @param {HTMLCanvasElement} canvas 
   * @returns {Promise<{current: number, max: number, percent: number}|null>}
   */
  async readHP(canvas) {
    if (!this.initialized) await this.init();
    if (!canvas) return null;

    try {
      const { data: { text } } = await this.worker.recognize(canvas);
      const cleanText = text.trim();

      // Match opponent HP%
      const percentMatch = cleanText.match(/(\d+)\s*%/);
      if (percentMatch) {
        const percent = Math.min(100, Math.max(0, parseInt(percentMatch[1], 10)));
        return { current: percent, max: 100, percent };
      }

      // Match player HP
      const hpMatch = cleanText.match(/(\d+)\s*\/\s*(\d+)/);
      if (hpMatch) {
        const current = parseInt(hpMatch[1], 10);
        const max = parseInt(hpMatch[2], 10);
        if (max > 0) {
          const percent = Math.min(100, Math.max(0, Math.round((current / max) * 100)));
          return { current, max, percent };
        }
      }

      return null;
    } catch (err) {
      console.error("OCR Error:", err);
      return null;
    }
  }

  /**
   * Read HP for all active Pokemon
   * @param {Array<HTMLCanvasElement>} regions Array of canvases
   * @returns {Promise<Array<Object|null>>}
   */
  async readAllHP(regions) {
    return Promise.all(regions.map(canvas => this.readHP(canvas)));
  }

  /**
   * Terminate the worker
   */
  async destroy() {
    if (this.worker) {
      await this.worker.terminate();
      this.worker = null;
      this.initialized = false;
    }
  }
}
