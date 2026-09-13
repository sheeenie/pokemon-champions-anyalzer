import SwiftUI

/// A type's glyph on its palette colour, optionally labelled.
private struct TypeBadge: View {
    let type: String
    var text: String? = nil
    var size: CGFloat = 13
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let glyph = TypeIcons.glyph(type) {
                Image(nsImage: glyph)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
            } else {
                Text(type.prefix(1).uppercased())
                    .font(.system(size: size * 0.8, weight: .heavy))
                    .foregroundColor(.white)
            }
            if let text {
                Text(text)
                    .font(.system(size: size * 0.75, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(TypePalette.color(type).opacity(dimmed ? 0.5 : 1))
        .cornerRadius(4)
    }
}

/// Full type badge with the name spelled out, for the Pokemon's own typing.
private struct TypeNameBadge: View {
    let type: String

    var body: some View {
        HStack(spacing: 4) {
            if let glyph = TypeIcons.glyph(type) {
                Image(nsImage: glyph)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: 13, height: 13)
            }
            Text(type.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(TypePalette.color(type))
        .cornerRadius(4)
    }
}

private struct ChipRow<Content: View>: View {
    let label: String
    let labelColor: Color
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        if count > 0 {
            HStack(alignment: .center, spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 44, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 4) {
            ChipRow(label: "WEAK",
                    labelColor: Color(red: 0.95, green: 0.42, blue: 0.42),
                    count: m.quadWeak.count + m.weak.count) {
                ForEach(m.quadWeak, id: \.self) { TypeBadge(type: $0, text: "×4") }
                ForEach(m.weak, id: \.self) { TypeBadge(type: $0, text: "×2") }
            }
            ChipRow(label: "RESIST",
                    labelColor: Color(red: 0.45, green: 0.78, blue: 0.60),
                    count: m.resist.count + m.quadResist.count) {
                ForEach(m.quadResist, id: \.self) { TypeBadge(type: $0, text: "×¼", dimmed: true) }
                ForEach(m.resist, id: \.self) { TypeBadge(type: $0, text: "×½", dimmed: true) }
            }
            ChipRow(label: "IMMUNE",
                    labelColor: Color(red: 0.62, green: 0.62, blue: 0.70),
                    count: m.immune.count) {
                ForEach(m.immune, id: \.self) { TypeBadge(type: $0, text: "0", dimmed: true) }
            }
        }
    }
}

/// What a species becomes if it Mega Evolves: new typing, stat changes, and -
/// only when the typing actually changes - the weaknesses that come with it,
/// since that is the part a player cannot infer from the base card.
private struct MegaRow: View {
    let base: Species
    let mega: Species

    private var deltas: [(String, Int)] {
        zip(base.baseStats.ordered, mega.baseStats.ordered)
            .map { ($0.0, $1.1 - $0.1) }
            .filter { $0.1 != 0 }
    }

    private var typingChanged: Bool { mega.types != base.types }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(mega.form.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(Color(red: 0.98, green: 0.80, blue: 0.35))
                    .lineLimit(1)
                    .fixedSize()
                ForEach(mega.types, id: \.self) { TypeBadge(type: $0, size: 11) }
                Spacer(minLength: 0)
                Text("\(mega.bst)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(spacing: 7) {
                ForEach(deltas, id: \.0) { stat in
                    HStack(spacing: 2) {
                        Text(stat.0)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                        Text(stat.1 > 0 ? "+\(stat.1)" : "\(stat.1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(stat.1 > 0
                                             ? Color(red: 0.49, green: 0.83, blue: 0.55)
                                             : Color(red: 0.90, green: 0.45, blue: 0.45))
                    }
                }
                Spacer(minLength: 0)
            }

            if typingChanged {
                let m = TypeChart.grouped(defending: mega.types)
                ChipRow(label: "→WEAK",
                        labelColor: Color(red: 0.95, green: 0.42, blue: 0.42),
                        count: m.quadWeak.count + m.weak.count) {
                    ForEach(m.quadWeak, id: \.self) { TypeBadge(type: $0, text: "×4", size: 11) }
                    ForEach(m.weak, id: \.self) { TypeBadge(type: $0, text: "×2", size: 11) }
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(occupant.species.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if occupant.species.isShiny {
                    Text("✦")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.83, blue: 0.35))
                }
                Spacer(minLength: 0)
                Text("\(occupant.species.bst)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            HStack(spacing: 5) {
                ForEach(occupant.species.types, id: \.self) { TypeNameBadge(type: $0) }
                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                ForEach(occupant.species.baseStats.ordered, id: \.0) { stat in
                    StatRow(label: stat.0, value: stat.1)
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            MatchupSection(types: occupant.species.types)

            let megas = PokedexStore.shared.megaForms(for: occupant.species)
            if !megas.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(megas, id: \.key) { mega in
                        MegaRow(base: occupant.species, mega: mega)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .cornerRadius(9)
    }
}

private struct EmptyCard: View {
    var body: some View {
        Text("Unidentified")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(Color.white.opacity(0.03))
            .cornerRadius(9)
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
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(alignment: .top, spacing: 14) {
                SideColumn(title: "OPPONENT",
                           accent: Color(red: 0.93, green: 0.31, blue: 0.45),
                           slots: [.opponent1, .opponent2],
                           occupants: battle.slots)
                SideColumn(title: "YOUR SIDE",
                           accent: Color(red: 0.36, green: 0.71, blue: 0.95),
                           slots: [.player1, .player2],
                           occupants: battle.slots)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }
}
