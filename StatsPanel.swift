import SwiftUI

/// Colours matching the standard Pokemon type palette.
private let typeColors: [String: Color] = [
    "normal": Color(red: 0.66, green: 0.65, blue: 0.48),
    "fire": Color(red: 0.94, green: 0.50, blue: 0.19),
    "water": Color(red: 0.39, green: 0.56, blue: 0.94),
    "electric": Color(red: 0.97, green: 0.82, blue: 0.17),
    "grass": Color(red: 0.48, green: 0.78, blue: 0.30),
    "ice": Color(red: 0.59, green: 0.85, blue: 0.84),
    "fighting": Color(red: 0.76, green: 0.18, blue: 0.16),
    "poison": Color(red: 0.64, green: 0.24, blue: 0.63),
    "ground": Color(red: 0.88, green: 0.75, blue: 0.41),
    "flying": Color(red: 0.66, green: 0.56, blue: 0.95),
    "psychic": Color(red: 0.98, green: 0.34, blue: 0.53),
    "bug": Color(red: 0.65, green: 0.73, blue: 0.10),
    "rock": Color(red: 0.71, green: 0.63, blue: 0.21),
    "ghost": Color(red: 0.45, green: 0.34, blue: 0.59),
    "dragon": Color(red: 0.44, green: 0.21, blue: 0.99),
    "dark": Color(red: 0.44, green: 0.34, blue: 0.27),
    "steel": Color(red: 0.72, green: 0.72, blue: 0.81),
    "fairy": Color(red: 0.93, green: 0.60, blue: 0.67),
]

private func typeColor(_ type: String) -> Color { typeColors[type] ?? .gray }

/// Three-letter abbreviations keep matchup chips scannable at a glance.
private let typeAbbrev: [String: String] = [
    "normal": "NRM", "fire": "FIR", "water": "WAT", "electric": "ELE",
    "grass": "GRS", "ice": "ICE", "fighting": "FGT", "poison": "PSN",
    "ground": "GRD", "flying": "FLY", "psychic": "PSY", "bug": "BUG",
    "rock": "RCK", "ghost": "GHO", "dragon": "DRA", "dark": "DRK",
    "steel": "STL", "fairy": "FAI",
]

private struct TypeChip: View {
    let type: String

    var body: some View {
        Text(type.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(typeColor(type))
            .cornerRadius(4)
    }
}

/// Compact chip used in the matchup rows, optionally badged with a multiplier.
private struct MatchupChip: View {
    let type: String
    var badge: String? = nil
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(typeAbbrev[type] ?? type.prefix(3).uppercased())
                .font(.system(size: 10, weight: .bold))
            if let badge {
                Text(badge).font(.system(size: 9, weight: .heavy))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(typeColor(type).opacity(dimmed ? 0.45 : 1.0))
        .cornerRadius(3)
    }
}

/// Wraps chips onto fixed-width rows. There are at most a handful per band,
/// so simple chunking beats a full flow layout here.
private struct ChipRow<Content: View>: View {
    let label: String
    let labelColor: Color
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        if count > 0 {
            HStack(alignment: .top, spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 46, alignment: .leading)
                    .padding(.top, 2)
                HStack(spacing: 3) { content() }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MatchupSection: View {
    let types: [String]

    var body: some View {
        let m = TypeChart.grouped(defending: types)
        VStack(alignment: .leading, spacing: 3) {
            ChipRow(label: "WEAK",
                    labelColor: Color(red: 0.95, green: 0.42, blue: 0.42),
                    count: m.quadWeak.count + m.weak.count) {
                ForEach(m.quadWeak, id: \.self) { MatchupChip(type: $0, badge: "4") }
                ForEach(m.weak, id: \.self) { MatchupChip(type: $0) }
            }
            ChipRow(label: "RESIST",
                    labelColor: Color(red: 0.45, green: 0.78, blue: 0.60),
                    count: m.resist.count + m.quadResist.count) {
                ForEach(m.quadResist, id: \.self) { MatchupChip(type: $0, badge: "¼", dimmed: true) }
                ForEach(m.resist, id: \.self) { MatchupChip(type: $0, dimmed: true) }
            }
            ChipRow(label: "IMMUNE",
                    labelColor: Color(red: 0.62, green: 0.62, blue: 0.70),
                    count: m.immune.count) {
                ForEach(m.immune, id: \.self) { MatchupChip(type: $0, badge: "0", dimmed: true) }
            }
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: Int

    /// 255 is the highest base stat in the games, so bars stay comparable
    /// across cards rather than rescaling per Pokemon.
    private var fraction: Double { min(Double(value) / 255.0, 1) }

    private var barColor: Color {
        switch value {
        case ..<60: return Color(red: 0.85, green: 0.33, blue: 0.31)
        case ..<90: return Color(red: 0.90, green: 0.65, blue: 0.22)
        case ..<120: return Color(red: 0.55, green: 0.76, blue: 0.29)
        default: return Color(red: 0.29, green: 0.70, blue: 0.62)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 30, alignment: .leading)
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 30, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 7)
        }
    }
}

private struct PokemonCard: View {
    let occupant: SlotOccupant

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(occupant.species.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text("\(occupant.species.bst)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(spacing: 5) {
                ForEach(occupant.species.types, id: \.self) { TypeChip(type: $0) }
                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                ForEach(occupant.species.baseStats.ordered, id: \.0) { stat in
                    StatRow(label: stat.0, value: stat.1)
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            MatchupSection(types: occupant.species.types)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
}

private struct EmptyCard: View {
    var body: some View {
        Text("Unidentified")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
    }
}

private struct SideColumn: View {
    let title: String
    let accent: Color
    let slots: [BattleSlot]
    let occupants: [BattleSlot: SlotOccupant]

    /// In singles only the outer slot is used, so an inner slot with no
    /// occupant is hidden rather than shown as unidentified.
    private var visible: [BattleSlot] {
        let filled = slots.filter { occupants[$0] != nil }
        return filled.isEmpty ? [slots[slots.count - 1]] : filled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(0.9)
            }
            ForEach(visible, id: \.self) { slot in
                if let occupant = occupants[slot] {
                    PokemonCard(occupant: occupant)
                } else {
                    EmptyCard()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsPanel: View {
    @ObservedObject var battle: BattleStateTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(battle.format.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.75))

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    SideColumn(title: "OPPONENT",
                               accent: Color(red: 0.93, green: 0.31, blue: 0.45),
                               slots: [.opponent1, .opponent2],
                               occupants: battle.slots)
                    SideColumn(title: "YOUR SIDE",
                               accent: Color(red: 0.36, green: 0.71, blue: 0.95),
                               slots: [.player1, .player2],
                               occupants: battle.slots)
                }
            }
        }
        .padding(12)
        .frame(width: 500)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }
}
