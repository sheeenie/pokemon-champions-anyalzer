export class UIRenderer {
  constructor() {
    this.elements = {
      btnCapture: document.getElementById('btn-capture'),
      statusDot: document.getElementById('status-dot'),
      statusText: document.getElementById('status-text'),
      videoContainer: document.getElementById('video-container'),
      welcomeModal: document.getElementById('welcome-modal'),
      calibrationOverlay: document.getElementById('calibration-overlay'),
      opponentSection: document.getElementById('opponent-section'),
      playerSection: document.getElementById('player-section'),
      matchupSection: document.getElementById('matchup-section'),
      tipsSection: document.getElementById('tips-section'),
      statusOcr: document.getElementById('status-ocr'),
      statusMatches: document.getElementById('status-matches'),
      statusFps: document.getElementById('status-fps'),
      statusCache: document.getElementById('status-cache'),
    };
  }

  capitalize(str) {
    if (!str) return '';
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  setBattleFormat(isDoubleBattle) {
    const opp2 = document.getElementById('opponent-card-2');
    const player2 = document.getElementById('player-card-2');
    if (opp2) opp2.style.display = isDoubleBattle ? 'block' : 'none';
    if (player2) player2.style.display = isDoubleBattle ? 'block' : 'none';
    
    const btnSingle = document.getElementById('btn-format-single');
    const btnDouble = document.getElementById('btn-format-double');
    if (btnSingle) {
      btnSingle.className = !isDoubleBattle ? 'btn btn-primary active' : 'btn btn-secondary';
    }
    if (btnDouble) {
      btnDouble.className = isDoubleBattle ? 'btn btn-primary active' : 'btn btn-secondary';
    }
  }

  formatStatName(stat) {
    const map = {
      'hp': 'HP',
      'attack': 'Atk',
      'defense': 'Def',
      'special-attack': 'SpA',
      'special-defense': 'SpD',
      'speed': 'Spe'
    };
    return map[stat] || stat;
  }

  getStatColor(stat) {
    const colors = {
      'hp': '#ef4444',
      'attack': '#f97316',
      'defense': '#eab308',
      'special-attack': '#3b82f6',
      'special-defense': '#22c55e',
      'speed': '#ec4899'
    };
    return colors[stat] || '#8899aa';
  }

  getHPColor(percent) {
    if (percent > 50) return '#22c55e';
    if (percent > 25) return '#f59e0b';
    return '#ef4444';
  }

  getEffectivenessClass(multiplier) {
    if (multiplier >= 4) return 'eff-4x';
    if (multiplier >= 2) return 'eff-2x';
    if (multiplier === 1) return 'eff-1x';
    if (multiplier === 0.5) return 'eff-05x';
    if (multiplier <= 0.25 && multiplier > 0) return 'eff-025x';
    if (multiplier === 0) return 'eff-0x';
    return 'eff-1x';
  }

  getEffectivenessLabel(multiplier) {
    if (multiplier === 0.5) return '½×';
    if (multiplier === 0.25) return '¼×';
    return `${multiplier}×`;
  }

  renderPokemonCard(containerId, data) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (!data) {
      container.className = 'pokemon-card empty';
      container.innerHTML = 'Waiting...';
      return;
    }

    const typesHtml = data.types.map(t => `<span class="type-badge type-${t}">${t}</span>`).join('');
    
    const statsHtml = Object.entries(data.stats || {}).map(([name, val]) => {
      const width = Math.min(100, (val / 255) * 100);
      return `
        <div class="stat-row">
          <span class="stat-label">${this.formatStatName(name)}</span>
          <div class="stat-bar-bg">
            <div class="stat-bar-fill" style="width: ${width}%; background-color: ${this.getStatColor(name)}"></div>
          </div>
          <span class="stat-value">${val}</span>
        </div>
      `;
    }).join('');

    const hpPercent = data.hp ? (data.hp.current / data.hp.max) * 100 : 100;
    const hpHtml = data.hp ? `
      <div class="hp-container">
        <div class="hp-label">
          <span>HP</span>
          <span>${data.hp.current}/${data.hp.max}</span>
        </div>
        <div class="hp-track">
          <div class="hp-fill" style="width: ${hpPercent}%; background-color: ${this.getHPColor(hpPercent)}"></div>
        </div>
      </div>
    ` : '';

    container.className = 'pokemon-card card-enter';
    container.innerHTML = `
      <div class="card-header">
        <div class="sprite-container">
          ${data.sprite ? `<img src="${data.sprite}" class="pokemon-sprite" alt="${data.name}">` : '???'}
        </div>
        <div class="pokemon-info">
          <div class="pokemon-name">${this.capitalize(data.name)}</div>
          <div class="type-badges">${typesHtml}</div>
        </div>
      </div>
      ${hpHtml}
      <div class="stats-container">
        ${statsHtml}
      </div>
    `;
  }

  renderMatchupMatrix(playerPokemon, opponentPokemon, matchups) {
    if (!this.elements.matchupSection) return;
    
    if (!playerPokemon || !opponentPokemon || !matchups || playerPokemon.length === 0 || opponentPokemon.length === 0) {
      this.elements.matchupSection.className = 'matrix-container empty';
      this.elements.matchupSection.innerHTML = 'Waiting for battle data...';
      return;
    }

    this.elements.matchupSection.className = 'matrix-container';

    let html = `<div class="matchup-grid">`;
    
    // Header row
    html += `<div class="matrix-cell matrix-header">Vs</div>`;
    opponentPokemon.forEach(opp => {
      html += `<div class="matrix-cell matrix-header">${opp ? this.capitalize(opp.name) : '???'}</div>`;
    });

    // Rows
    playerPokemon.forEach((player, i) => {
      html += `<div class="matrix-cell matrix-header">${player ? this.capitalize(player.name) : '???'}</div>`;
      opponentPokemon.forEach((opp, j) => {
        if (player && opp && matchups && matchups[player.name] && matchups[player.name][opp.name] !== undefined) {
          const mult = matchups[player.name][opp.name];
          const cssClass = this.getEffectivenessClass(mult);
          const label = this.getEffectivenessLabel(mult);
          html += `<div class="matrix-cell ${cssClass}">${label}</div>`;
        } else {
          html += `<div class="matrix-cell">-</div>`;
        }
      });
    });

    html += `</div>`;
    this.elements.matchupSection.innerHTML = html;
  }

  renderBattleTips(tips) {
    if (!this.elements.tipsSection) return;

    if (!tips || tips.length === 0) {
      this.elements.tipsSection.className = 'tips-container empty';
      this.elements.tipsSection.innerHTML = 'Waiting for battle data...';
      return;
    }

    this.elements.tipsSection.className = 'tips-container';
    
    const html = tips.map(tip => `
      <div class="tip-card tip-${tip.priority || 'medium'} card-enter">
        <div class="tip-icon">${tip.icon || '💡'}</div>
        <div class="tip-content">
          <p>${tip.text}</p>
        </div>
      </div>
    `).join('');

    this.elements.tipsSection.innerHTML = html;
  }

  updateHP(slotId, hpData) {
    // Left as stub for dynamic OCR updates
  }

  updateStatus(data) {
    if (data.ocr && this.elements.statusOcr) this.elements.statusOcr.textContent = data.ocr;
    if (data.matched !== undefined && data.total !== undefined && this.elements.statusMatches) {
      this.elements.statusMatches.textContent = `${data.matched}/${data.total}`;
    }
    if (data.fps !== undefined && this.elements.statusFps) this.elements.statusFps.textContent = data.fps;
    if (data.cacheSize !== undefined && this.elements.statusCache) this.elements.statusCache.textContent = `${data.cacheSize} items`;
  }

  showWelcome() {
    if (this.elements.welcomeModal) this.elements.welcomeModal.classList.remove('hidden');
  }

  hideWelcome() {
    if (this.elements.welcomeModal) this.elements.welcomeModal.classList.add('hidden');
  }

  showCalibration() {
    if (this.elements.calibrationOverlay) this.elements.calibrationOverlay.classList.remove('hidden');
  }

  hideCalibration() {
    if (this.elements.calibrationOverlay) this.elements.calibrationOverlay.classList.add('hidden');
  }

  setCapturing(isCapturing) {
    if (this.elements.btnCapture) {
      this.elements.btnCapture.textContent = isCapturing ? 'Stop Capture' : 'Start Capture';
      this.elements.btnCapture.className = isCapturing ? 'btn btn-primary active' : 'btn btn-primary';
    }
    if (this.elements.statusDot) {
      this.elements.statusDot.className = isCapturing ? 'dot active' : 'dot';
    }
    if (this.elements.statusText) {
      this.elements.statusText.textContent = isCapturing ? 'Capturing' : 'Ready';
    }
    if (this.elements.videoContainer) {
      this.elements.videoContainer.className = isCapturing ? 'video-container active' : 'video-container placeholder';
    }
  }

  showPlaceholder() {
    if (this.elements.videoContainer) {
      this.elements.videoContainer.innerHTML = `
        <div id="video-placeholder" class="placeholder-content">
          <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="pulse-icon"><rect x="2" y="2" width="20" height="20" rx="2.18" ry="2.18"></rect><line x1="7" y1="2" x2="7" y2="22"></line><line x1="17" y1="2" x2="17" y2="22"></line><line x1="2" y1="12" x2="22" y2="12"></line><line x1="2" y1="7" x2="7" y2="7"></line><line x1="2" y1="17" x2="7" y2="17"></line><line x1="17" y1="17" x2="22" y2="17"></line><line x1="17" y1="7" x2="22" y2="7"></line></svg>
          <p>Click Start Capture to mirror your screen</p>
        </div>
      `;
    }
  }

  clearDashboard() {
    this.renderPokemonCard('opponent-card-1', null);
    this.renderPokemonCard('opponent-card-2', null);
    this.renderPokemonCard('player-card-1', null);
    this.renderPokemonCard('player-card-2', null);
    this.renderMatchupMatrix([], [], null);
    this.renderBattleTips([]);
  }
}
