import Foundation

/// A move that can be estimated: fixed base power, known type and class.
struct MoveData: Codable {
    let power: Int
    let type: String
    /// "physical" or "special". Status moves are not in the file at all.
    let category: String
    let zh: String
    /// Move order, when it is not the usual 0. Absent from the file for the
    /// 229 of 249 moves that do not have one.
    let priority: Int?
    /// PokeAPI's target, which in doubles decides who is hit and whether the
    /// damage is reduced. Optional so data generated before it decodes.
    let target: String?
    /// Nil for a move that never misses.
    let accuracy: Int?
    let pp: Int?
    /// What it does beyond damage. English is PokeAPI's short effect, which is
    /// precise; Chinese is the flavour text, the only Chinese there is.
    let descEn: String?
    let descZh: String?

    var isPhysical: Bool { category == "physical" }

    /// Chinese falls back to English: PokeAPI has no Chinese text at all for
    /// the newer moves, and the English description beats an empty panel.
    func effect(_ lang: Lang) -> String {
        if lang == .zh, let zh = descZh, !zh.isEmpty { return zh }
        return descEn ?? ""
    }

    var reach: MoveReach {
        switch target {
        case "all-opponents": return .allOpponents
        case "all-other-pokemon": return .allOthers
        default: return .single
        }
    }

    func name(_ en: String, _ lang: Lang) -> String {
        lang == .zh && !zh.isEmpty ? zh : en
    }
}

/// Who a move hits when there is more than one Pokemon on the other side.
enum MoveReach {
    /// One Pokemon of the attacker's choosing.
    case single
    /// Both opponents at once - Rock Slide, Heat Wave, Dazzling Gleam.
    case allOpponents
    /// Both opponents and the attacker's own partner - Earthquake, Surf,
    /// Discharge, Explosion.
    case allOthers

    var hitsAlly: Bool { self == .allOthers }
    var isSpread: Bool { self != .single }
}

/// What a move does to one Pokemon.
struct TargetDamage {
    let species: Species
    /// Share of that Pokemon's HP, 0...1, at the lowest and highest roll.
    let minFraction: Double
    let maxFraction: Double
    /// The same thing in hit points, for the hover panel: a card has room only
    /// for the percentage, but the raw numbers are what a player counts in.
    let minHP: Int
    let maxHP: Int
    let targetHP: Int
    /// 0 when it cannot be hit at all, which is shown rather than hidden: an
    /// Earthquake that misses one of the two is the point of the row.
    let effectiveness: Double
}

/// One estimated attack, against everything it would hit.
struct DamageEstimate: Identifiable {
    let move: String
    let data: MoveData
    /// Share of this Pokemon's teams carrying the move, when known.
    let usage: Double?
    /// The opposing Pokemon, in the order their cards appear.
    let targets: [TargetDamage]
    /// The attacker's own partner, when the move would catch them too.
    let ally: TargetDamage?
    /// True when the 0.75x reduction for hitting several Pokemon applies.
    let reduced: Bool

    var id: String { move }

    /// The worst it does to anything, which is what colours the row.
    var maxFraction: Double {
        (targets.map(\.maxFraction) + [ally?.maxFraction ?? 0]).max() ?? 0
    }
    /// Singles, or a doubles field with only one Pokemon left opposite.
    var isSingleTarget: Bool { targets.count == 1 && ally == nil }
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

    /// What one move does to one Pokemon, before the roll is split out.
    private static func damage(_ data: MoveData, attacker: Species, defender: Species,
                               reduced: Bool) -> TargetDamage {
        let effectiveness = TypeChart.matchups(defending: defender.types)[data.type] ?? 1
        let defenderHP = hp(base: defender.baseStats.hp, dex: defender.dex)
        guard effectiveness > 0 else {
            return TargetDamage(species: defender, minFraction: 0, maxFraction: 0,
                                minHP: 0, maxHP: 0, targetHP: defenderHP, effectiveness: 0)
        }

        let attack = stat(base: data.isPhysical ? attacker.baseStats.atk : attacker.baseStats.spa)
        let defense = stat(base: data.isPhysical ? defender.baseStats.def : defender.baseStats.spd)

        let stab = attacker.types.contains(data.type) ? 1.5 : 1.0
        let raw = Double(base(power: data.power, attack: attack, defense: defense))
            * stab * effectiveness * (reduced ? 0.75 : 1)

        // The game's damage roll is 85%...100%.
        let low = max(1.0, (raw * 0.85).rounded(.down))
        let high = max(1.0, raw.rounded(.down))
        return TargetDamage(species: defender,
                            minFraction: low / Double(defenderHP),
                            maxFraction: high / Double(defenderHP),
                            minHP: Int(low), maxHP: Int(high), targetHP: defenderHP,
                            effectiveness: effectiveness)
    }

    /// Estimates `move` against everything it would hit, or nil when it can
    /// touch none of them.
    ///
    /// A move that hits several Pokemon at once does 0.75x to each, and only
    /// while there is more than one to hit: Rock Slide into a lone survivor is
    /// back to full damage. Earthquake and its kind also hit the attacker's own
    /// partner, which is worth seeing before the turn rather than after it.
    static func estimate(move: String, data: MoveData, attacker: Species,
                         foes: [Species], ally: Species? = nil,
                         usage: Double? = nil) -> DamageEstimate? {
        let reach = data.reach
        let ally = reach.hitsAlly ? ally : nil
        let hit = reach.isSpread ? foes.count + (ally == nil ? 0 : 1) : 1
        let reduced = reach.isSpread && hit > 1

        let targets = foes.map {
            damage(data, attacker: attacker, defender: $0, reduced: reduced)
        }
        let allyHit = ally.map {
            damage(data, attacker: attacker, defender: $0, reduced: reduced)
        }
        guard targets.contains(where: { $0.effectiveness > 0 }) || (allyHit?.effectiveness ?? 0) > 0
        else { return nil }

        return DamageEstimate(move: move, data: data, usage: usage,
                              targets: targets, ally: allyHit, reduced: reduced)
    }

    /// The moves this Pokemon most often carries, most-used first, up to
    /// `limit` - the snapshot holds ten per Pokemon, and the panel scrolls
    /// them, so the cap only exists to bound a surprising data file.
    ///
    /// Usage order, not damage order. How often a move is actually run already
    /// prices in everything this calculator ignores - accuracy above all, but
    /// also PP, side effects and how the move fits a real set. A 4x hit off a
    /// move almost nobody carries is a number, not a threat.
    static func topMoves(for attacker: Species, against foes: [Species],
                         ally: Species? = nil,
                         usage: [UsageMove], limit: Int = 12) -> [DamageEstimate] {
        usage
            .compactMap { entry -> DamageEstimate? in
                guard let data = UsageStore.shared.move(entry.name) else { return nil }
                return estimate(move: entry.name, data: data, attacker: attacker,
                                foes: foes, ally: ally, usage: entry.pct)
            }
            .prefix(limit)
            .map { $0 }
    }
}
