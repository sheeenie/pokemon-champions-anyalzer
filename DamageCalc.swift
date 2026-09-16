import Foundation

/// A move that can be estimated: fixed base power, known type and class.
struct MoveData: Codable {
    let power: Int
    let type: String
    /// "physical" or "special". Status moves are not in the file at all.
    let category: String
    let zh: String

    var isPhysical: Bool { category == "physical" }

    func name(_ en: String, _ lang: Lang) -> String {
        lang == .zh && !zh.isEmpty ? zh : en
    }
}

/// One estimated attack: what it does to the Pokemon across from it.
struct DamageEstimate: Identifiable {
    let move: String
    let data: MoveData
    /// Share of the defender's HP, 0...1, at the lowest and highest roll.
    let minFraction: Double
    let maxFraction: Double
    let effectiveness: Double
    /// Share of this Pokemon's teams carrying the move, when known.
    let usage: Double?

    var id: String { move }
}

/// Rough damage estimates for Pokemon Champions singles.
///
/// Champions fixes every battle at level 50 with perfect IVs, so the only
/// unknowns are Stat Points, nature and held item. None of those are modelled
/// here: this deliberately assumes a bare Pokemon - 0 SP, neutral nature, no
/// item, no ability or field effects - so the numbers are a floor for a real
/// attacker, not a prediction. A fully invested attacker hits meaningfully
/// harder, so treat these as "at least this much" rather than "about this".
enum DamageCalc {
    static let level = 50

    /// Stat at level 50 with perfect IVs and no Stat Points.
    static func stat(base: Int) -> Int { (2 * base + 31) * level / 100 + 5 }

    /// HP has its own formula, and Shedinja is always 1.
    static func hp(base: Int, dex: Int) -> Int {
        dex == 292 ? 1 : (2 * base + 31) * level / 100 + level + 10
    }

    /// The damage a move does, before the random roll, as raw HP.
    ///
    /// The standard formula, with the level-50 term folded in:
    /// floor(2 * 50 / 5 + 2) is 22.
    private static func base(power: Int, attack: Int, defense: Int) -> Int {
        22 * power * attack / defense / 50 + 2
    }

    /// Estimates `move` used by `attacker` against `defender`, or nil when it
    /// cannot land at all - the defender is immune, or the attacker's typing
    /// makes the move unusable data.
    static func estimate(move: String, data: MoveData,
                         attacker: Species, defender: Species,
                         usage: Double? = nil) -> DamageEstimate? {
        let effectiveness = TypeChart.matchups(defending: defender.types)[data.type] ?? 1
        guard effectiveness > 0 else { return nil }

        let attack = stat(base: data.isPhysical ? attacker.baseStats.atk : attacker.baseStats.spa)
        let defense = stat(base: data.isPhysical ? defender.baseStats.def : defender.baseStats.spd)
        let defenderHP = hp(base: defender.baseStats.hp, dex: defender.dex)

        let stab = attacker.types.contains(data.type) ? 1.5 : 1.0
        let raw = Double(base(power: data.power, attack: attack, defense: defense))
            * stab * effectiveness

        // The game's damage roll is 85%...100%.
        let low = max(1.0, (raw * 0.85).rounded(.down))
        let high = max(1.0, raw.rounded(.down))

        return DamageEstimate(
            move: move,
            data: data,
            minFraction: low / Double(defenderHP),
            maxFraction: high / Double(defenderHP),
            effectiveness: effectiveness,
            usage: usage
        )
    }

    /// The moves this Pokemon most often carries, most-used first, up to
    /// `limit` - the snapshot holds ten per Pokemon, and the panel scrolls
    /// them, so the cap only exists to bound a surprising data file.
    ///
    /// Usage order, not damage order. How often a move is actually run already
    /// prices in everything this calculator ignores - accuracy above all, but
    /// also PP, side effects and how the move fits a real set. A 4x hit off a
    /// move almost nobody carries is a number, not a threat.
    static func topMoves(for attacker: Species, against defender: Species,
                         usage: [UsageMove], limit: Int = 12) -> [DamageEstimate] {
        usage
            .compactMap { entry -> DamageEstimate? in
                guard let data = UsageStore.shared.move(entry.name) else { return nil }
                return estimate(move: entry.name, data: data,
                                attacker: attacker, defender: defender,
                                usage: entry.pct)
            }
            .prefix(limit)
            .map { $0 }
    }
}
