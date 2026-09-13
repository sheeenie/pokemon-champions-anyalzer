import Foundation

/// Type effectiveness (Gen 6 onward).
enum TypeChart {

    static let allTypes = [
        "normal", "fire", "water", "electric", "grass", "ice",
        "fighting", "poison", "ground", "flying", "psychic", "bug",
        "rock", "ghost", "dragon", "dark", "steel", "fairy",
    ]

    /// Attacking type -> defending types it does not hit neutrally.
    /// Anything absent is 1x.
    private static let attack: [String: [String: Double]] = [
        "normal": ["rock": 0.5, "ghost": 0, "steel": 0.5],
        "fire": ["fire": 0.5, "water": 0.5, "grass": 2, "ice": 2, "bug": 2,
                 "rock": 0.5, "dragon": 0.5, "steel": 2],
        "water": ["fire": 2, "water": 0.5, "grass": 0.5, "ground": 2,
                  "rock": 2, "dragon": 0.5],
        "electric": ["water": 2, "electric": 0.5, "grass": 0.5, "ground": 0,
                     "flying": 2, "dragon": 0.5],
        "grass": ["fire": 0.5, "water": 2, "grass": 0.5, "poison": 0.5,
                  "ground": 2, "flying": 0.5, "bug": 0.5, "rock": 2,
                  "dragon": 0.5, "steel": 0.5],
        "ice": ["fire": 0.5, "water": 0.5, "grass": 2, "ice": 0.5, "ground": 2,
                "flying": 2, "dragon": 2, "steel": 0.5],
        "fighting": ["normal": 2, "ice": 2, "poison": 0.5, "flying": 0.5,
                     "psychic": 0.5, "bug": 0.5, "rock": 2, "ghost": 0,
                     "dark": 2, "steel": 2, "fairy": 0.5],
        "poison": ["grass": 2, "poison": 0.5, "ground": 0.5, "rock": 0.5,
                   "ghost": 0.5, "steel": 0, "fairy": 2],
        "ground": ["fire": 2, "electric": 2, "grass": 0.5, "poison": 2,
                   "flying": 0, "bug": 0.5, "rock": 2, "steel": 2],
        "flying": ["electric": 0.5, "grass": 2, "fighting": 2, "bug": 2,
                   "rock": 0.5, "steel": 0.5],
        "psychic": ["fighting": 2, "poison": 2, "psychic": 0.5, "dark": 0,
                    "steel": 0.5],
        "bug": ["fire": 0.5, "grass": 2, "fighting": 0.5, "poison": 0.5,
                "flying": 0.5, "psychic": 2, "ghost": 0.5, "dark": 2,
                "steel": 0.5, "fairy": 0.5],
        "rock": ["fire": 2, "ice": 2, "fighting": 0.5, "ground": 0.5,
                 "flying": 2, "bug": 2, "steel": 0.5],
        "ghost": ["normal": 0, "psychic": 2, "ghost": 2, "dark": 0.5],
        "dragon": ["dragon": 2, "steel": 0.5, "fairy": 0],
        "dark": ["fighting": 0.5, "psychic": 2, "ghost": 2, "dark": 0.5,
                 "fairy": 0.5],
        "steel": ["fire": 0.5, "water": 0.5, "electric": 0.5, "ice": 2,
                  "rock": 2, "steel": 0.5, "fairy": 2],
        "fairy": ["fire": 0.5, "fighting": 2, "poison": 0.5, "dragon": 2,
                  "dark": 2, "steel": 0.5],
    ]

    /// What each attacking type does to a Pokemon with these defending types,
    /// keeping only the non-neutral results.
    static func matchups(defending types: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for attacker in allTypes {
            var multiplier = 1.0
            for defender in types {
                multiplier *= attack[attacker]?[defender] ?? 1
            }
            if multiplier != 1 { result[attacker] = multiplier }
        }
        return result
    }

    /// Grouped for display, worst first within each band.
    struct Matchups {
        var quadWeak: [String] = []   // 4x
        var weak: [String] = []       // 2x
        var resist: [String] = []     // 1/2x
        var quadResist: [String] = [] // 1/4x
        var immune: [String] = []     // 0x
    }

    static func grouped(defending types: [String]) -> Matchups {
        var out = Matchups()
        for (type, multiplier) in matchups(defending: types).sorted(by: { $0.key < $1.key }) {
            switch multiplier {
            case 0: out.immune.append(type)
            case 0.25: out.quadResist.append(type)
            case 0.5: out.resist.append(type)
            case 2: out.weak.append(type)
            default:
                if multiplier >= 4 { out.quadWeak.append(type) }
            }
        }
        return out
    }
}
