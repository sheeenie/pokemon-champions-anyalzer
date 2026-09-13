import SwiftUI

/// A type's glyph on its palette colour, optionally labelled.
private struct TypeBadge: View {
    let type: String
    var text: String? = nil
    var size: CGFloat = 16

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
                    .font(.system(size: size * 0.85, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(TypePalette.color(type))
        .cornerRadius(4)
    }
}

/// Full type badge with the name spelled out, for the Pokemon's own typing.
private struct TypeNameBadge: View {
    let type: String
    @Environment(\.lang) private var lang

    var body: some View {
        HStack(spacing: 4) {
            if let glyph = TypeIcons.glyph(type) {
                Image(nsImage: glyph)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: 13, height: 13)
            }
            Text(L10n.type(type, lang))
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
            HStack(alignment: .top, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 56, alignment: .leading)
                    .padding(.top, 5)
                // Wraps: in the four-column doubles layout a card is too narrow
                // for a long weakness or resist row on one line.
                FlowLayout(spacing: 3, lineSpacing: 4) { content() }
            }
        }
    }
}

/// One ability. Hovering opens a popover describing what it does.
///
/// A popover rather than `.help`: the system tooltip waits about a second,
/// only appears while this app is frontmost - and during play the game has
/// focus - and renders in small system text.
private struct AbilityChip: View {
    let ability: Ability
    @Environment(\.lang) private var lang
    @State private var hovering = false

    var body: some View {
        let description = ability.description(lang)
        HStack(spacing: 4) {
            Text(ability.name(lang))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if ability.hidden {
                Text(L10n.text(.hidden, lang))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(hovering ? 0.24 : (ability.hidden ? 0.06 : 0.13)))
        .cornerRadius(4)
        .onHover { hovering = $0 && !description.isEmpty }
        // Anchored below the chip so the popover never sits under the cursor;
        // if it did, it would end the hover that opened it and flicker.
        .popover(isPresented: $hovering, arrowEdge: .bottom) {
            // Values passed explicitly: popover content is presented in its
            // own window and should not rely on inheriting the environment.
            AbilityDescription(name: ability.name(lang),
                               hiddenLabel: ability.hidden ? L10n.text(.hidden, lang) : nil,
                               description: description)
        }
    }
}

private struct AbilityDescription: View {
    let name: String
    let hiddenLabel: String?
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .font(.system(size: 15, weight: .bold))
                if let hiddenLabel {
                    Text(hiddenLabel)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.secondary)
                }
            }
            Text(description)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}

private struct AbilityRow: View {
    let abilities: [Ability]
    @Environment(\.lang) private var lang

    var body: some View {
        ChipRow(label: L10n.text(.ability, lang),
                labelColor: Color(red: 0.70, green: 0.72, blue: 0.95),
                count: abilities.count) {
            ForEach(Array(abilities.enumerated()), id: \.offset) { _, ability in
                AbilityChip(ability: ability)
            }
        }
    }
}

private struct MatchupSection: View {
    let types: [String]
    @Environment(\.lang) private var lang

    var body: some View {
        let m = TypeChart.grouped(defending: types)
        VStack(alignment: .leading, spacing: 4) {
            ChipRow(label: L10n.text(.weak, lang),
                    labelColor: Color(red: 0.95, green: 0.42, blue: 0.42),
                    count: m.quadWeak.count + m.weak.count) {
                ForEach(m.quadWeak, id: \.self) { TypeBadge(type: $0, text: "×4") }
                ForEach(m.weak, id: \.self) { TypeBadge(type: $0, text: "×2") }
            }
            ChipRow(label: L10n.text(.resist, lang),
                    labelColor: Color(red: 0.45, green: 0.78, blue: 0.60),
                    count: m.resist.count + m.quadResist.count) {
                ForEach(m.quadResist, id: \.self) { TypeBadge(type: $0, text: "×¼") }
                ForEach(m.resist, id: \.self) { TypeBadge(type: $0, text: "×½") }
            }
            ChipRow(label: L10n.text(.immune, lang),
                    labelColor: Color(red: 0.62, green: 0.62, blue: 0.70),
                    count: m.immune.count) {
                ForEach(m.immune, id: \.self) { TypeBadge(type: $0, text: "0") }
            }
        }
    }
}

/// What a species becomes if it Mega Evolves: new typing, ability, stat
/// changes, and - only when the typing actually changes - the weaknesses that
/// come with it, since that is the part a player cannot infer from the base card.
private struct MegaRow: View {
    let base: Species
    let mega: Species
    @Environment(\.lang) private var lang

    /// All six stats in fixed columns, value above its change from the base,
    /// so columns line up and can be read straight down. Unchanged stats stay
    /// in place (shown as a dash) rather than being dropped.
    private var columns: [(label: String, value: Int, delta: Int)] {
        zip(base.baseStats.ordered, mega.baseStats.ordered)
            .map { (label: $1.0, value: $1.1, delta: $1.1 - $0.1) }
    }

    private var typingChanged: Bool { mega.types != base.types }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(mega.formLabel(lang))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Color(red: 0.98, green: 0.80, blue: 0.35))
                    .lineLimit(1)
                    .fixedSize()
                ForEach(mega.types, id: \.self) { TypeNameBadge(type: $0) }
                Spacer(minLength: 0)
                Text("\(L10n.text(.bst, lang)) \(mega.bst)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            AbilityRow(abilities: mega.abilityList)

            Grid(horizontalSpacing: 4, verticalSpacing: 2) {
                GridRow {
                    ForEach(columns, id: \.label) { col in
                        VStack(spacing: 1) {
                            Text(L10n.stat(col.label, lang))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(col.value)")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                GridRow {
                    ForEach(columns, id: \.label) { col in
                        Text(col.delta == 0 ? "–" : (col.delta > 0 ? "+\(col.delta)" : "\(col.delta)"))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(col.delta == 0
                                             ? .white.opacity(0.3)
                                             : col.delta > 0
                                                ? Color(red: 0.49, green: 0.83, blue: 0.55)
                                                : Color(red: 0.90, green: 0.45, blue: 0.45))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)

            if typingChanged {
                let m = TypeChart.grouped(defending: mega.types)
                ChipRow(label: L10n.text(.megaWeak, lang),
                        labelColor: Color(red: 0.95, green: 0.42, blue: 0.42),
                        count: m.quadWeak.count + m.weak.count) {
                    ForEach(m.quadWeak, id: \.self) { TypeBadge(type: $0, text: "×4") }
                    ForEach(m.weak, id: \.self) { TypeBadge(type: $0, text: "×2") }
                }
            }
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: Int
    @Environment(\.lang) private var lang

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
            Text(L10n.stat(label, lang))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 32, alignment: .leading)
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
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                // The reference sprite that actually won the match, so a wrong
                // identification is obvious at a glance against the mirror.
                if let sprite = PokedexStore.shared.icon(for: occupant.species.key) {
                    Image(nsImage: NSImage(cgImage: sprite,
                                           size: NSSize(width: sprite.width, height: sprite.height)))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(occupant.species.displayName(lang))
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
                }
            }

            AbilityRow(abilities: occupant.species.abilityList)

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
    @Environment(\.lang) private var lang

    var body: some View {
        Text(L10n.text(.unidentified, lang))
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
    /// Doubles: one column per slot, so four cards sit side by side instead of
    /// two tall cards stacked per side, which ran off the bottom of the window.
    let sideBySide: Bool

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
            if sideBySide {
                // Every slot keeps its column, empty or not, in the same
                // left-to-right order as the name plates in the game.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(slots, id: \.self) { slot in
                        card(for: slot)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            } else {
                ForEach(visible, id: \.self) { card(for: $0) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func card(for slot: BattleSlot) -> some View {
        if let occupant = occupants[slot] {
            PokemonCard(occupant: occupant)
        } else {
            EmptyCard()
        }
    }
}

private func sideAccent(_ side: BattleSide) -> Color {
    switch side {
    case .opponent: return Color(red: 0.93, green: 0.31, blue: 0.45)
    case .player: return Color(red: 0.36, green: 0.71, blue: 0.95)
    }
}

/// Lays children out left to right, wrapping onto new lines when out of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct SpeedEntry: Identifiable {
    let id: String
    let species: Species
    let side: BattleSide
}

/// Every Pokemon seen this battle plus the Megas each could become, fastest
/// first, for reading turn order at a glance.
private struct SpeedList: View {
    let seen: [String: SeenPokemon]
    @Environment(\.lang) private var lang

    private var entries: [SpeedEntry] {
        var byID: [String: SpeedEntry] = [:]
        for pokemon in seen.values {
            for species in [pokemon.species] + PokedexStore.shared.megaForms(for: pokemon.species) {
                // Keyed without shininess, and per side: a Pokemon seen both as
                // itself and already Mega Evolved must not list that Mega twice,
                // while a mirror match keeps one entry for each side.
                let id = "\(pokemon.side)-\(species.dex)-\(species.form)"
                if byID[id] == nil {
                    byID[id] = SpeedEntry(id: id, species: species, side: pokemon.side)
                }
            }
        }
        return byID.values.sorted {
            let a = $0.species.baseStats.spe, b = $1.species.baseStats.spe
            return a != b ? a > b : $0.id < $1.id
        }
    }

    var body: some View {
        let list = entries
        if !list.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.text(.speed, lang))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(Color(red: 0.49, green: 0.83, blue: 0.55))
                    .fixedSize()
                FlowLayout(spacing: 4, lineSpacing: 6) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 4) {
                            SpeedChip(entry: entry)
                            // Kept with its chip so a wrap never starts a line
                            // with a dangling separator.
                            if index < list.count - 1 {
                                let tie = entry.species.baseStats.spe
                                    == list[index + 1].species.baseStats.spe
                                Text(tie ? "=" : ">")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(tie ? 0.9 : 0.45))
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(9)
        }
    }
}

private struct SpeedChip: View {
    let entry: SpeedEntry
    @Environment(\.lang) private var lang

    private var isMega: Bool { entry.species.form.contains("Mega") }

    var body: some View {
        HStack(spacing: 5) {
            if let sprite = PokedexStore.shared.icon(for: entry.species.key) {
                Image(nsImage: NSImage(cgImage: sprite,
                                       size: NSSize(width: sprite.width, height: sprite.height)))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            }
            Text(entry.species.displayName(lang))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isMega ? Color(red: 0.98, green: 0.80, blue: 0.35) : .white)
                .lineLimit(1)
            Text("\(entry.species.baseStats.spe)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(sideAccent(entry.side).opacity(0.18))
        .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(sideAccent(entry.side).opacity(0.75), lineWidth: 1))
        .cornerRadius(5)
    }
}

struct StatsPanel: View {
    @ObservedObject var battle: BattleStateTracker
    /// Remembered across launches.
    @AppStorage("language") private var lang: Lang = .en

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.format(battle.format, lang))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Picker("", selection: $lang) {
                    ForEach(Lang.allCases) { Text($0.pickerLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SpeedList(seen: battle.seen)

            HStack(alignment: .top, spacing: 14) {
                SideColumn(title: L10n.text(.opponent, lang),
                           accent: sideAccent(.opponent),
                           slots: [.opponent1, .opponent2],
                           occupants: battle.slots,
                           sideBySide: battle.format == .doubles)
                SideColumn(title: L10n.text(.yourSide, lang),
                           accent: sideAccent(.player),
                           slots: [.player1, .player2],
                           occupants: battle.slots,
                           sideBySide: battle.format == .doubles)
            }
            Spacer(minLength: 0)
        }
        .environment(\.lang, lang)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }
}
