/**
 * Perceptual Hashing Engine
 */
export class ImageHasher {
  /**
   * Computes a 64-bit dHash of the image
   * @param {HTMLImageElement|HTMLCanvasElement|ImageData} imageSource 
   * @param {HTMLCanvasElement} canvas 
   * @returns {string} 16-character hex string
   */
  static computeDHash(imageSource, canvas) {
    if (!canvas) {
      canvas = document.createElement('canvas');
    }
    canvas.width = 9;
    canvas.height = 8;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    
    // If it's ImageData, put it first then resize? No, ImageData to canvas is putImageData but we want resize.
    // Easiest is to draw via an intermediate canvas if it's ImageData.
    if (imageSource instanceof ImageData) {
      const tempCanvas = document.createElement('canvas');
      tempCanvas.width = imageSource.width;
      tempCanvas.height = imageSource.height;
      tempCanvas.getContext('2d').putImageData(imageSource, 0, 0);
      ctx.drawImage(tempCanvas, 0, 0, 9, 8);
    } else {
      ctx.drawImage(imageSource, 0, 0, 9, 8);
    }

    const imageData = ctx.getImageData(0, 0, 9, 8).data;
    let hash = '';
    
    // Grayscale
    const grays = new Uint8Array(72);
    for (let i = 0; i < 72; i++) {
      const idx = i * 4;
      const r = imageData[idx];
      const g = imageData[idx + 1];
      const b = imageData[idx + 2];
      grays[i] = Math.round(0.299 * r + 0.587 * g + 0.114 * b);
    }

    for (let row = 0; row < 8; row++) {
      for (let col = 0; col < 8; col++) {
        const left = grays[row * 9 + col];
        const right = grays[row * 9 + col + 1];
        hash += (left > right ? '1' : '0');
      }
    }

    // Binary string to hex
    let hexHash = '';
    for (let i = 0; i < 64; i += 4) {
      const nibble = hash.substring(i, i + 4);
      hexHash += parseInt(nibble, 2).toString(16);
    }

    return hexHash;
  }

  /**
   * Computes a normalized HSV color histogram
   * @param {HTMLImageElement|HTMLCanvasElement|ImageData} imageSource 
   * @param {HTMLCanvasElement} canvas 
   * @returns {Float32Array}
   */
  static computeColorHistogram(imageSource, canvas) {
    if (!canvas) {
      canvas = document.createElement('canvas');
    }
    canvas.width = 64;
    canvas.height = 64;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    
    if (imageSource instanceof ImageData) {
      const tempCanvas = document.createElement('canvas');
      tempCanvas.width = imageSource.width;
      tempCanvas.height = imageSource.height;
      tempCanvas.getContext('2d').putImageData(imageSource, 0, 0);
      ctx.drawImage(tempCanvas, 0, 0, 64, 64);
    } else {
      ctx.drawImage(imageSource, 0, 0, 64, 64);
    }

    const data = ctx.getImageData(0, 0, 64, 64).data;
    const hist = new Float32Array(256);
    let validPixels = 0;

    for (let i = 0; i < data.length; i += 4) {
      const r = data[i] / 255;
      const g = data[i + 1] / 255;
      const b = data[i + 2] / 255;
      const a = data[i + 3];

      if (a < 128) continue; // Skip very transparent pixels

      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      const d = max - min;
      let h = 0;
      let s = max === 0 ? 0 : d / max;
      let v = max;

      if (max !== min) {
        switch (max) {
          case r: h = (g - b) / d + (g < b ? 6 : 0); break;
          case g: h = (b - r) / d + 2; break;
          case b: h = (r - g) / d + 4; break;
        }
        h /= 6;
      }

      // H: 0-7, S: 0-7, V: 0-3
      const hBin = Math.min(7, Math.floor(h * 8));
      const sBin = Math.min(7, Math.floor(s * 8));
      const vBin = Math.min(3, Math.floor(v * 4));

      // 8 * 4 = 32
      const binIndex = hBin * 32 + sBin * 4 + vBin;
      hist[binIndex]++;
      validPixels++;
    }

    if (validPixels > 0) {
      for (let i = 0; i < 256; i++) {
        hist[i] /= validPixels;
      }
    }

    return hist;
  }

  /**
   * Computes Hamming distance between two hex hashes
   * @param {string} hexHash1 
   * @param {string} hexHash2 
   * @returns {number}
   */
  static hammingDistance(hexHash1, hexHash2) {
    let distance = 0;
    for (let i = 0; i < 16; i++) {
      const val1 = parseInt(hexHash1[i], 16);
      const val2 = parseInt(hexHash2[i], 16);
      let xor = val1 ^ val2;
      while (xor > 0) {
        distance += xor & 1;
        xor >>= 1;
      }
    }
    return distance;
  }

  /**
   * Computes histogram intersection
   * @param {Float32Array|Array} hist1 
   * @param {Float32Array|Array} hist2 
   * @returns {number} 0.0 - 1.0
   */
  static histogramIntersection(hist1, hist2) {
    let sum = 0;
    for (let i = 0; i < 256; i++) {
      sum += Math.min(hist1[i], hist2[i]);
    }
    return sum;
  }
}
