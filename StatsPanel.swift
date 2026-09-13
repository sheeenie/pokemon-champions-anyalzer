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

private struct TypeChip: View {
    let type: String

    var body: some View {
        Text(type.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((typeColors[type] ?? .gray).opacity(0.95))
            .cornerRadius(3)
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
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 26, alignment: .leading)
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 26, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

private struct PokemonCard: View {
    let occupant: SlotOccupant

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(occupant.species.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 4) {
                ForEach(occupant.species.types, id: \.self) { TypeChip(type: $0) }
                Spacer(minLength: 0)
                Text("BST \(occupant.species.bst)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            VStack(spacing: 3) {
                ForEach(occupant.species.baseStats.ordered, id: \.0) { stat in
                    StatRow(label: stat.0, value: stat.1)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(7)
    }
}

private struct EmptyCard: View {
    var body: some View {
        Text("Unidentified")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color.white.opacity(0.03))
            .cornerRadius(7)
    }
}

private struct SideSection: View {
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.8)
            }
            ForEach(visible, id: \.self) { slot in
                if let occupant = occupants[slot] {
                    PokemonCard(occupant: occupant)
                } else {
                    EmptyCard()
                }
            }
        }
    }
}

struct StatsPanel: View {
    @ObservedObject var battle: BattleStateTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(battle.format.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.75))

            SideSection(title: "OPPONENT",
                        accent: Color(red: 0.93, green: 0.31, blue: 0.45),
                        slots: [.opponent1, .opponent2],
                        occupants: battle.slots)

            SideSection(title: "YOUR SIDE",
                        accent: Color(red: 0.36, green: 0.71, blue: 0.95),
                        slots: [.player1, .player2],
                        occupants: battle.slots)

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(width: 210)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }
}
