/**
 * Gemini Vision API Client
 */
export class GeminiClient {
  constructor(matcher) {
    this.matcher = matcher;
    this.apiKey = localStorage.getItem('pca_gemini_api_key') || '';
    this.model = 'gemini-1.5-flash-latest';
  }

  setApiKey(key) {
    this.apiKey = key;
    localStorage.setItem('pca_gemini_api_key', key);
  }

  hasApiKey() {
    return !!this.apiKey;
  }

  /**
   * Identify a Pokémon from a canvas crop using Gemini Vision
   * @param {HTMLCanvasElement} canvas 
   * @returns {Promise<string|null>} Returns the PokéAPI name or null
   */
  async identifyPokemon(canvas) {
    if (!this.hasApiKey()) {
      console.warn('Gemini API key not set.');
      return null;
    }

    // Convert canvas to base64 JPEG
    const base64Data = canvas.toDataURL('image/jpeg', 0.8).replace(/^data:image\/jpeg;base64,/, '');

    // Get list of valid names from the database
    const validNames = this.matcher.database.map(p => p.name).join(', ');

    const prompt = `You are a Pokémon identification expert.
I am providing a small cropped screenshot from a Pokémon game UI showing a Pokémon's face next to a health bar.
Your task is to identify exactly which Pokémon this is.

IMPORTANT: You must reply ONLY with the exact name from the following list. Do not include any other text, punctuation, or explanation.
If there is NO Pokémon visible in the image (just an empty background), reply ONLY with the word: NONE

Valid names: ${validNames}

If you are not sure, make your best guess from the list. Respond with ONLY the exact name string or NONE.`;

    try {
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          contents: [{
            parts: [
              { text: prompt },
              {
                inline_data: {
                  mime_type: 'image/jpeg',
                  data: base64Data
                }
              }
            ]
          }],
          generationConfig: {
            temperature: 0.1, // low temperature for precise factual matching
            maxOutputTokens: 20
          }
        })
      });

      if (!response.ok) {
        const err = await response.json();
        console.error('Gemini API Error:', err);
        return null;
      }

      const data = await response.json();
      const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim().toLowerCase();
      
      if (!text || text === 'none') return null;

      // Validate against the list to ensure it's exact
      const match = this.matcher.database.find(p => p.name === text);
      if (match) {
        console.log(`[Gemini] Successfully identified: ${text}`);
        return text;
      } else {
        console.warn(`[Gemini] Returned invalid name: "${text}"`);
        // Try fuzzy matching just in case
        const fuzzyMatch = this.matcher.database.find(p => text.includes(p.name) || p.name.includes(text));
        if (fuzzyMatch) {
          console.log(`[Gemini] Fuzzy matched to: ${fuzzyMatch.name}`);
          return fuzzyMatch.name;
        }
        return null;
      }
    } catch (e) {
      console.error('Gemini Request failed:', e);
      return null;
    }
  }
}
