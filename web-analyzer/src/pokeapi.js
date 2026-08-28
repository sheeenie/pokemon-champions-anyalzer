/**
 * PokéAPI Client
 */
export class PokeAPIClient {
  constructor() {
    this.cache = new Map();
    this.typeNames = [
      'normal', 'fire', 'water', 'electric', 'grass', 'ice', 'fighting',
      'poison', 'ground', 'flying', 'psychic', 'bug', 'rock', 'ghost',
      'dragon', 'dark', 'steel', 'fairy'
    ];
  }

  getCacheSize() {
    return this.cache.size;
  }

  cacheKey(endpoint) {
    return `pokeapi_${endpoint}`;
  }

  async fetchCached(url) {
    if (this.cache.has(url)) {
      return this.cache.get(url);
    }
    const key = this.cacheKey(url);
    const local = localStorage.getItem(key);
    if (local) {
      const data = JSON.parse(local);
      this.cache.set(url, data);
      return data;
    }

    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
      const data = await res.json();
      this.cache.set(url, data);
      try {
        localStorage.setItem(key, JSON.stringify(data));
      } catch (e) {
        // Handle localStorage quota exceeded
      }
      return data;
    } catch (error) {
      console.error(`Failed to fetch ${url}`, error);
      return null;
    }
  }

  async getPokemon(nameOrId) {
    const data = await this.fetchCached(`https://pokeapi.co/api/v2/pokemon/${nameOrId}`);
    if (!data) return null;

    const stats = {};
    data.stats.forEach(s => {
      stats[s.stat.name] = s.base_stat;
    });

    return {
      id: data.id,
      name: data.name,
      types: data.types.map(t => t.type.name),
      stats,
      abilities: data.abilities.map(a => ({ name: a.ability.name, isHidden: a.is_hidden })),
      sprite: data.sprites.front_default,
      height: data.height,
      weight: data.weight
    };
  }

  async getTypeMatchups(defenderTypes) {
    const multipliers = {};
    this.typeNames.forEach(t => multipliers[t] = 1);

    for (const type of defenderTypes) {
      const typeData = await this.fetchCached(`https://pokeapi.co/api/v2/type/${type}`);
      if (!typeData) continue;

      const damageRelations = typeData.damage_relations;
      
      damageRelations.double_damage_from.forEach(t => multipliers[t.name] *= 2);
      damageRelations.half_damage_from.forEach(t => multipliers[t.name] *= 0.5);
      damageRelations.no_damage_from.forEach(t => multipliers[t.name] *= 0);
    }

    const result = {
      quadruple: [],
      double: [],
      neutral: [],
      half: [],
      quarter: [],
      immune: []
    };

    for (const [type, mult] of Object.entries(multipliers)) {
      if (mult === 4) result.quadruple.push(type);
      else if (mult === 2) result.double.push(type);
      else if (mult === 1) result.neutral.push(type);
      else if (mult === 0.5) result.half.push(type);
      else if (mult === 0.25) result.quarter.push(type);
      else if (mult === 0) result.immune.push(type);
    }

    return result;
  }

  async getMegaStats(pokemonName) {
    if (!pokemonName.includes('-mega')) return null;
    return this.getPokemon(pokemonName);
  }
}
