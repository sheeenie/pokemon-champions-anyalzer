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

/// One estimated attack: name, share of the target's HP, and hits to KO.
private struct DamageRow: View {
    let estimate: DamageEstimate
    @Environment(\.lang) private var lang

    /// Coloured by how much it hurts, on the same reading as the type matchups
    /// above it: red is the one that ends the turn badly.
    private var tint: Color {
        switch estimate.maxFraction {
        case 1.0...: return Color(red: 0.98, green: 0.36, blue: 0.36)
        case 0.5...: return Color(red: 0.98, green: 0.62, blue: 0.29)
        case 0.25...: return Color(red: 0.96, green: 0.85, blue: 0.40)
        default: return .white.opacity(0.65)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(estimate.data.name(estimate.move, lang))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // How often it is carried: this is the order of the list, so it
            // has to be visible or the ordering looks arbitrary.
            if let usage = estimate.usage {
                Text(String(format: "%.0f%%", usage))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.32))
            }
            Spacer(minLength: 4)
            Text(String(format: "%.0f-%.0f%%",
                        estimate.minFraction * 100, estimate.maxFraction * 100))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(tint)
            Text(estimate.koLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 52, alignment: .trailing)
        }
        .frame(height: DamageSection.rowHeight)
    }
}

/// What this Pokemon can do to the one across from it, using the moves it is
/// actually seen carrying. Singles only: in doubles there are two Pokemon on
/// each side, so there is no single counterpart to aim at.
private struct DamageSection: View {
    let attacker: Species
    let defender: Species
    @Environment(\.lang) private var lang

    /// Row geometry is fixed so the scroll view can be sized to whole rows,
    /// rather than cutting one in half and looking like a rendering mistake.
    static let rowHeight: CGFloat = 17
    private static let rowSpacing: CGFloat = 5
    /// Rows before it scrolls. Every move a Pokemon is seen carrying is listed,
    /// but a card cannot grow without pushing the Mega previews off screen, so
    /// the rest are a scroll away.
    private static let visibleRows = 4

    var body: some View {
        let estimates = DamageCalc.topMoves(for: attacker, against: defender,
                                            usage: UsageStore.shared.moves(for: attacker.key))
        if !estimates.isEmpty {
            let shown = min(estimates.count, DamageSection.visibleRows)
            let height = CGFloat(shown) * DamageSection.rowHeight
                + CGFloat(max(0, shown - 1)) * DamageSection.rowSpacing
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(L10n.text(.damage, lang))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(0.8)
                    Text("→ \(defender.displayName(lang))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // macOS hides scrollbars until you scroll, so without this
                    // there is nothing to say the list continues.
                    if estimates.count > DamageSection.visibleRows {
                        HStack(spacing: 2) {
                            Text("\(estimates.count)")
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    }
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: DamageSection.rowSpacing) {
                        ForEach(estimates) { DamageRow(estimate: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: height)
                Text(L10n.text(.damageNote, lang))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
    }
}

private struct PokemonCard: View {
    let occupant: SlotOccupant
    /// False once this Pokemon's side has Mega Evolved, since it then can't.
    var showMegas = true
    /// The Pokemon across from this one, in singles. Nil in doubles.
    var facing: Species? = nil
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

            if let facing {
                Divider().overlay(Color.white.opacity(0.12))
                DamageSection(attacker: occupant.species, defender: facing)
            }

            let megas = showMegas ? PokedexStore.shared.megaForms(for: occupant.species) : []
            if !megas.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(megas.enumerated()), id: \.element.key) { index, mega in
                        if index > 0 {
                            // Separates alternative Megas (X and Y, Mega and Mega Z),
                            // which otherwise run together into one block.
                            Divider().overlay(Color.white.opacity(0.25))
                        }
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
    /// This side has Mega Evolved this battle, so its cards hide Mega previews.
    let megaUsed: Bool
    /// Doubles: one column per slot, so four cards sit side by side instead of
    /// two tall cards stacked per side, which ran off the bottom of the window.
    let sideBySide: Bool
    /// The Pokemon this side's card is up against, in singles. Nil in doubles.
    var facing: Species? = nil

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
            PokemonCard(occupant: occupant, showMegas: !megaUsed, facing: facing)
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

/// Sides that have Mega Evolved this battle. Only one Pokemon per side can Mega
/// Evolve in a battle, so once a side has, its other Pokemon can't.
private func sidesThatMegaEvolved(_ seen: [String: SeenPokemon]) -> Set<BattleSide> {
    Set(seen.values.filter { $0.species.form.contains("Mega") }.map(\.side))
}

/// Identity of a speed list entry: per side, ignoring shininess.
private func speedID(_ side: BattleSide, _ species: Species) -> String {
    "\(side)-\(species.dex)-\(species.form)"
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
    /// IDs of the Pokemon currently showing on a card, which the list highlights.
    let onField: Set<String>
    @Environment(\.lang) private var lang

    private var entries: [SpeedEntry] {
        var byID: [String: SpeedEntry] = [:]
        let megaUsed = sidesThatMegaEvolved(seen)
        // Grouped per side and species, so a mirror match keeps each side separate.
        let groups = Dictionary(grouping: seen.values) { "\($0.side)-\($0.species.dex)" }
        for sightings in groups.values {
            // Once a Pokemon has Mega Evolved, its base form and any Mega it did
            // not choose no longer matter, so only the Mega that appeared is listed.
            // Its side's other Pokemon then lose their possible Megas too.
            let evolved = sightings.filter { $0.species.form.contains("Mega") }
            let candidates: [(side: BattleSide, species: Species)] = evolved.isEmpty
                ? sightings.flatMap { pokemon -> [(side: BattleSide, species: Species)] in
                    let megas = megaUsed.contains(pokemon.side)
                        ? [] : PokedexStore.shared.megaForms(for: pokemon.species)
                    return ([pokemon.species] + megas).map { (side: pokemon.side, species: $0) }
                }
                : evolved.map { (side: $0.side, species: $0.species) }
            for candidate in candidates {
                // Keyed without shininess, so a shiny and its normal art don't list twice.
                let id = speedID(candidate.side, candidate.species)
                if byID[id] == nil {
                    byID[id] = SpeedEntry(id: id, species: candidate.species, side: candidate.side)
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
                            SpeedChip(entry: entry, onField: onField.contains(entry.id))
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
    /// On the field right now, as opposed to switched out or a Mega it could
    /// still become. These stand out so current turn order reads at a glance.
    let onField: Bool
    @Environment(\.lang) private var lang

    var body: some View {
        HStack(spacing: 5) {
            if let sprite = PokedexStore.shared.icon(for: entry.species.key) {
                Image(nsImage: NSImage(cgImage: sprite,
                                       size: NSSize(width: sprite.width, height: sprite.height)))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .opacity(onField ? 1 : 0.7)
            }
            Text(entry.species.displayName(lang))
                .font(.system(size: 13, weight: onField ? .bold : .semibold))
                .foregroundColor(onField ? .white : .white.opacity(0.6))
                .lineLimit(1)
            Text("\(entry.species.baseStats.spe)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(onField ? .white : .white.opacity(0.6))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(sideAccent(entry.side).opacity(onField ? 0.45 : 0.10))
        .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(sideAccent(entry.side).opacity(onField ? 1 : 0.4),
                            lineWidth: onField ? 2 : 1))
        .cornerRadius(5)
    }
}

struct StatsPanel: View {
    @ObservedObject var battle: BattleStateTracker
    /// Remembered across launches.
    @AppStorage("language") private var lang: Lang = .en

    private var megaUsed: Set<BattleSide> { sidesThatMegaEvolved(battle.seen) }

    /// In singles each card shows what its Pokemon does to the one opposite, so
    /// it has to know its counterpart. Doubles has two Pokemon a side and no
    /// single counterpart, so both come back nil and the section is left out.
    private var facing: (opponent: Species?, player: Species?) {
        guard battle.format == .singles else { return (nil, nil) }
        return (battle.slots.first { $0.key.side == .opponent }?.value.species,
                battle.slots.first { $0.key.side == .player }?.value.species)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.format(battle.format, lang))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                // Their data, their credit: the API's terms require it wherever
                // the numbers are shown, so it lives in the header rather than
                // under the cards, where a tall card can push it off screen.
                if battle.format == .singles {
                    Text(L10n.text(.usageCredit, lang))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.leading, 4)
                }
                Spacer()
                Picker("", selection: $lang) {
                    ForEach(Lang.allCases) { Text($0.pickerLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SpeedList(seen: battle.seen,
                      onField: Set(battle.slots.map { speedID($0.key.side, $0.value.species) }))

            HStack(alignment: .top, spacing: 14) {
                SideColumn(title: L10n.text(.opponent, lang),
                           accent: sideAccent(.opponent),
                           slots: [.opponent1, .opponent2],
                           occupants: battle.slots,
                           megaUsed: megaUsed.contains(.opponent),
                           sideBySide: battle.format == .doubles,
                           facing: facing.player)
                SideColumn(title: L10n.text(.yourSide, lang),
                           accent: sideAccent(.player),
                           slots: [.player1, .player2],
                           occupants: battle.slots,
                           megaUsed: megaUsed.contains(.player),
                           sideBySide: battle.format == .doubles,
                           facing: facing.opponent)
            }
            Spacer(minLength: 0)
        }
        .environment(\.lang, lang)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }
}
