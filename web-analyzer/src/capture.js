/**
 * Screen Capture Module
 */
export class ScreenCapture {
  constructor() {
    this.stream = null;
    this.videoElement = document.createElement('video');
    this.videoElement.autoplay = true;
    this.videoElement.muted = true;
    // Hidden video for internal canvas capture
    this.videoElement.style.display = 'none';
    this.canvas = document.createElement('canvas');
    this.ctx = this.canvas.getContext('2d');
  }

  /**
   * Starts capturing the screen
   * @returns {Promise<MediaStream>}
   */
  async startCapture() {
    try {
      this.stream = await navigator.mediaDevices.getDisplayMedia({
        video: { displaySurface: 'window', frameRate: { ideal: 30 } },
        audio: false
      });

      this.videoElement.srcObject = this.stream;
      await this.videoElement.play();

      const videoTrack = this.stream.getVideoTracks()[0];
      videoTrack.addEventListener('ended', () => {
        this.stopCapture();
      });

      return this.stream;
    } catch (err) {
      console.error("Error starting screen capture:", err);
      throw err;
    }
  }

  /**
   * Stops the screen capture
   */
  stopCapture() {
    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }
    this.videoElement.srcObject = null;
  }

  /**
   * Captures the current frame from the video
   * @returns {{canvas: HTMLCanvasElement, imageData: ImageData, width: number, height: number} | null}
   */
  captureFrame() {
    if (!this.isActive() || this.videoElement.videoWidth === 0) {
      return null;
    }

    const width = this.videoElement.videoWidth;
    const height = this.videoElement.videoHeight;

    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }

    this.ctx.drawImage(this.videoElement, 0, 0, width, height);
    const imageData = this.ctx.getImageData(0, 0, width, height);

    return {
      canvas: this.canvas,
      imageData,
      width,
      height
    };
  }

  /**
   * Returns whether the capture is active
   * @returns {boolean}
   */
  isActive() {
    return this.stream !== null && this.stream.active;
  }

  /**
   * Returns the video element for preview display
   * @returns {HTMLVideoElement}
   */
  getVideoElement() {
    return this.videoElement;
  }
}
