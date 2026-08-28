/**
 * Battle Analysis Engine
 */
export class BattleAnalyzer {
  constructor(pokeApiClient) {
    this.api = pokeApiClient;
  }

  /**
   * Analyze battle state
   * @param {Array} playerPokemon 
   * @param {Array} opponentPokemon 
   */
  async analyzeBattle(playerPokemon, opponentPokemon) {
    const matchups = [];
    const tips = [];
    const threats = [];
    const allPokemon = [...playerPokemon, ...opponentPokemon].filter(p => p !== null);

    // Calculate matchups
    for (const attacker of playerPokemon) {
      if (!attacker) continue;
      for (const defender of opponentPokemon) {
        if (!defender) continue;
        
        const effectiveness = await this.calculateOffensiveMatchup(attacker.types, defender.types);
        let label = 'neutral';
        if (effectiveness === 4) label = 'quad effective';
        else if (effectiveness === 2) label = 'super effective';
        else if (effectiveness === 0.5) label = 'not very effective';
        else if (effectiveness === 0.25) label = 'doubly resisted';
        else if (effectiveness === 0) label = 'immune';

        matchups.push({
          attacker: attacker.name,
          defender: defender.name,
          effectiveness,
          label
        });
      }
    }
    
    // Also consider opponents attacking player
    for (const attacker of opponentPokemon) {
      if (!attacker) continue;
      for (const defender of playerPokemon) {
        if (!defender) continue;
        
        const effectiveness = await this.calculateOffensiveMatchup(attacker.types, defender.types);
        if (effectiveness >= 2) {
          threats.push({
            source: attacker.name,
            target: defender.name,
            reason: `STAB ${attacker.types.join('/')} threatens ${defender.types.join('/')} type`
          });
        }
      }
    }

    const speedOrder = this.getSpeedOrder(allPokemon);
    const generatedTips = this.generateTips(matchups, speedOrder, playerPokemon, opponentPokemon);
    tips.push(...generatedTips);

    return {
      matchups,
      speedOrder,
      tips,
      threats
    };
  }

  async calculateOffensiveMatchup(attackerTypes, defenderTypes) {
    let bestMultiplier = 0;
    const matchups = await this.api.getTypeMatchups(defenderTypes);
    
    const multMap = {
      quadruple: 4,
      double: 2,
      neutral: 1,
      half: 0.5,
      quarter: 0.25,
      immune: 0
    };

    for (const attackerType of attackerTypes) {
      let currentMultiplier = 1; // Default
      for (const [key, typesList] of Object.entries(matchups)) {
        if (typesList.includes(attackerType)) {
          currentMultiplier = multMap[key];
          break;
        }
      }
      if (currentMultiplier > bestMultiplier) {
        bestMultiplier = currentMultiplier;
      }
    }

    return bestMultiplier;
  }

  generateTips(matchups, speedOrder, playerPokemon, opponentPokemon) {
    const tips = [];

    // Analyze speed
    const fastest = speedOrder[0];
    if (fastest) {
      const isPlayerFastest = playerPokemon.some(p => p && p.name === fastest);
      tips.push({
        priority: isPlayerFastest ? 'medium' : 'high',
        icon: '⚡',
        text: `${fastest.charAt(0).toUpperCase() + fastest.slice(1)} outspeeds all others`
      });
    }

    // High damage tips
    matchups.forEach(m => {
      if (m.effectiveness >= 2) {
        tips.push({
          priority: m.effectiveness === 4 ? 'high' : 'medium',
          icon: '🔥',
          text: `${m.attacker.charAt(0).toUpperCase() + m.attacker.slice(1)} hits ${m.defender.charAt(0).toUpperCase() + m.defender.slice(1)} for ${m.effectiveness}x damage`
        });
      }
    });

    return tips.sort((a, b) => {
      if (a.priority === 'high' && b.priority !== 'high') return -1;
      if (a.priority !== 'high' && b.priority === 'high') return 1;
      return 0;
    });
  }

  getSpeedOrder(allPokemon) {
    return allPokemon
      .slice()
      .sort((a, b) => (b.stats.speed || 0) - (a.stats.speed || 0))
      .map(p => p.name);
  }
}
