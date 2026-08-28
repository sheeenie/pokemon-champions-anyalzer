export class CalibrationManager {
  constructor(regionManager, captureManager) {
    this.regionManager = regionManager;
    this.captureManager = captureManager;
    this.container = document.getElementById('calibration-canvas-container');
    
    this.canvas = document.createElement('canvas');
    this.ctx = this.canvas.getContext('2d');
    
    this.canvas.style.width = '100%';
    this.canvas.style.maxWidth = 'calc(60vh * 16 / 9)';
    this.canvas.style.margin = '0 auto';
    this.canvas.style.display = 'block';
    this.canvas.style.cursor = 'crosshair';
    this.canvas.style.borderRadius = '8px';
    this.canvas.style.border = '2px solid rgba(255, 255, 255, 0.08)';
    
    if (this.container) {
      this.container.innerHTML = '';
      this.container.appendChild(this.canvas);
    }
    
    this.isActive = false;
    this.activeRegion = null;
    this.action = null; // 'drag' or 'resize'
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
    this.startW = 0;
    this.startH = 0;
    this.isDoubleBattle = true;
    
    this.setupEvents();
  }
  
  setupEvents() {
    this.canvas.addEventListener('mousedown', (e) => this.handlePointerDown(e));
    window.addEventListener('mousemove', (e) => this.handlePointerMove(e));
    window.addEventListener('mouseup', () => this.handlePointerUp());
    
    this.canvas.addEventListener('touchstart', (e) => {
      e.preventDefault();
      const touch = e.touches[0];
      this.handlePointerDown(touch, this.canvas.getBoundingClientRect());
    }, { passive: false });
    
    window.addEventListener('touchmove', (e) => {
      if (this.activeRegion) e.preventDefault();
      const touch = e.touches[0];
      this.handlePointerMove(touch);
    }, { passive: false });
    
    window.addEventListener('touchend', () => this.handlePointerUp());
  }
  
  getPointerCoords(e, rect = this.canvas.getBoundingClientRect()) {
    const scaleX = this.canvas.width / rect.width;
    const scaleY = this.canvas.height / rect.height;
    return {
      x: (e.clientX - rect.left) * scaleX,
      y: (e.clientY - rect.top) * scaleY
    };
  }
  
  handlePointerDown(e, rect = this.canvas.getBoundingClientRect()) {
    if (!this.isActive) return;
    
    const { x, y } = this.getPointerCoords(e, rect);
    const pixelRegions = this.regionManager.getRegions(this.canvas.width, this.canvas.height);
    
    // Check in reverse order so top-most is selected
    const entries = Object.entries(pixelRegions).reverse();
    
    for (const [name, r] of entries) {
      if (!this.isDoubleBattle && name.includes('SLOT_2')) continue;
      
      // Check if clicking resize handle (bottom right corner, 20x20px area)
      const handleSize = 20;
      if (x >= r.x + r.w - handleSize && x <= r.x + r.w + handleSize &&
          y >= r.y + r.h - handleSize && y <= r.y + r.h + handleSize) {
        this.activeRegion = name;
        this.action = 'resize';
        this.dragOffsetX = x;
        this.dragOffsetY = y;
        this.startW = this.regionManager.regions[name].w;
        this.startH = this.regionManager.regions[name].h;
        this.canvas.style.cursor = 'nwse-resize';
        return;
      }
      
      // Check if clicking inside region (drag)
      if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h) {
        this.activeRegion = name;
        this.action = 'drag';
        this.dragOffsetX = x - r.x;
        this.dragOffsetY = y - r.y;
        this.canvas.style.cursor = 'grabbing';
        return;
      }
    }
  }
  
  handlePointerMove(e) {
    if (!this.isActive || !this.activeRegion) {
      // Update cursor if hovering over resize handle
      if (this.isActive && !this.activeRegion) {
        const { x, y } = this.getPointerCoords(e);
        const pixelRegions = this.regionManager.getRegions(this.canvas.width, this.canvas.height);
        let hoverHandle = false;
        for (const [name, r] of Object.entries(pixelRegions)) {
          if (!this.isDoubleBattle && name.includes('SLOT_2')) continue;
          if (x >= r.x + r.w - 15 && x <= r.x + r.w + 15 && y >= r.y + r.h - 15 && y <= r.y + r.h + 15) {
            hoverHandle = true; break;
          }
        }
        this.canvas.style.cursor = hoverHandle ? 'nwse-resize' : 'crosshair';
      }
      return;
    }
    
    const rect = this.canvas.getBoundingClientRect();
    const { x, y } = this.getPointerCoords(e, rect);
    const currentReg = this.regionManager.regions[this.activeRegion];
    
    if (this.action === 'drag') {
      let pctX = (x - this.dragOffsetX) / this.canvas.width;
      let pctY = (y - this.dragOffsetY) / this.canvas.height;
      
      pctX = Math.max(0, Math.min(pctX, 1 - currentReg.w));
      pctY = Math.max(0, Math.min(pctY, 1 - currentReg.h));
      
      this.regionManager.setRegion(this.activeRegion, { ...currentReg, x: pctX, y: pctY });
    } 
    else if (this.action === 'resize') {
      const dx = (x - this.dragOffsetX) / this.canvas.width;
      const dy = (y - this.dragOffsetY) / this.canvas.height;
      
      let newW = Math.max(0.01, this.startW + dx);
      let newH = Math.max(0.01, this.startH + dy);
      
      // Ensure it doesn't go off screen
      newW = Math.min(newW, 1 - currentReg.x);
      newH = Math.min(newH, 1 - currentReg.y);
      
      this.regionManager.setRegion(this.activeRegion, { ...currentReg, w: newW, h: newH });
    }
  }
  
  handlePointerUp() {
    this.activeRegion = null;
    this.action = null;
    if (this.canvas) this.canvas.style.cursor = 'crosshair';
  }
  
  start() {
    this.isActive = true;
    this.loop();
  }
  
  stop() {
    this.isActive = false;
  }
  
  loop() {
    if (!this.isActive) return;
    const video = this.captureManager.getVideoElement();
    
    if (video && video.videoWidth > 0) {
      if (this.canvas.width !== video.videoWidth) {
        this.canvas.width = video.videoWidth;
        this.canvas.height = video.videoHeight;
      }
      this.ctx.drawImage(video, 0, 0, this.canvas.width, this.canvas.height);
    } else {
      if (this.canvas.width === 0) {
        this.canvas.width = 1280;
        this.canvas.height = 720;
      }
      this.ctx.fillStyle = '#111827';
      this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
      this.ctx.fillStyle = '#8899aa';
      this.ctx.font = '24px Inter, sans-serif';
      this.ctx.textAlign = 'center';
      this.ctx.fillText('Start screen capture to see preview', this.canvas.width / 2, this.canvas.height / 2);
    }
    
    const pixelRegions = this.regionManager.getRegions(this.canvas.width, this.canvas.height);
    
    for (const [name, r] of Object.entries(pixelRegions)) {
      if (!this.isDoubleBattle && name.includes('SLOT_2')) continue;
      
      const isActive = this.activeRegion === name;
      
      this.ctx.strokeStyle = isActive ? '#22c55e' : '#3b82f6';
      this.ctx.lineWidth = 3;
      this.ctx.setLineDash([6, 4]);
      this.ctx.strokeRect(r.x, r.y, r.w, r.h);
      
      this.ctx.fillStyle = isActive ? 'rgba(34, 197, 94, 0.2)' : 'rgba(59, 130, 246, 0.2)';
      this.ctx.fillRect(r.x, r.y, r.w, r.h);
      
      // Draw resize handle
      this.ctx.setLineDash([]);
      this.ctx.fillStyle = isActive ? '#22c55e' : '#3b82f6';
      this.ctx.fillRect(r.x + r.w - 8, r.y + r.h - 8, 16, 16);
      
      const label = name.replace(/_/g, ' ');
      const textWidth = this.ctx.measureText(label).width;
      this.ctx.fillStyle = 'rgba(0,0,0,0.7)';
      this.ctx.fillRect(r.x, r.y - 20, textWidth + 8, 20);
      
      this.ctx.fillStyle = '#ffffff';
      this.ctx.font = '14px Inter, sans-serif';
      this.ctx.textAlign = 'left';
      this.ctx.fillText(label, r.x + 4, r.y - 5);
    }
    
    this.ctx.setLineDash([]);
    requestAnimationFrame(() => this.loop());
  }
}
