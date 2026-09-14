import Foundation
import AppKit
import CoreGraphics

struct BaseStats: Codable {
    let hp: Int
    let atk: Int
    let def: Int
    let spa: Int
    let spd: Int
    let spe: Int

    var ordered: [(String, Int)] {
        [("HP", hp), ("Atk", atk), ("Def", def), ("SpA", spa), ("SpD", spd), ("Spe", spe)]
    }
}

struct Ability: Codable {
    let en: String
    let zh: String
    let descEn: String
    let descZh: String
    let hidden: Bool

    func name(_ lang: Lang) -> String { lang == .zh && !zh.isEmpty ? zh : en }
    func description(_ lang: Lang) -> String { lang == .zh && !descZh.isEmpty ? descZh : descEn }
}

struct Species: Codable {
    /// Unique per sprite file, so distinct artwork never shares an entry.
    let key: String
    let dex: Int
    /// English display name, with the form in parentheses where there is one.
    let name: String
    let form: String
    /// Traditional Chinese name. Not used for identification — it is what makes
    /// a match verifiable by eye against the Chinese text on the plate.
    let zhHant: String
    let types: [String]
    let baseStats: BaseStats
    let bst: Int

    /// Shiny artwork is a separate reference icon for the same species, because
    /// identification compares colour and a shiny is a recolour. Stats and
    /// typing are identical. Optional so older generated data still decodes.
    private let shiny: Bool?
    var isShiny: Bool { shiny ?? false }

    // Optional so data generated before these fields existed still decodes.
    private let nameZh: String?
    private let formZh: String?
    let abilities: [Ability]?

    var abilityList: [Ability] { abilities ?? [] }

    func displayName(_ lang: Lang) -> String {
        guard lang == .zh else { return name }
        return nameZh ?? (zhHant.isEmpty ? name : zhHant)
    }

    func formLabel(_ lang: Lang) -> String {
        lang == .zh ? (formZh ?? form) : form.uppercased()
    }
}

/// Loads the generated reference data produced by tools/fetch_pokedex.py, from
/// the resources embedded in the executable (see EmbeddedResources).
final class PokedexStore {
    static let shared = PokedexStore()

    private(set) var species: [Species] = []
    private var byKey: [String: Species] = [:]
    private var megasByDex: [Int: [Species]] = [:]
    private var iconCache: [String: CGImage] = [:]
    private let iconLock = NSLock()

    init() {
        load()
    }

    private func load() {
        guard let data = EmbeddedResources.data("pokedex.json") else {
            print("[pokedex] no pokedex.json found; run tools/fetch_pokedex.py")
            return
        }
        do {
            species = try JSONDecoder().decode([Species].self, from: data)
            byKey = Dictionary(uniqueKeysWithValues: species.map { ($0.key, $0) })
            // Shiny Megas are excluded: they are the same form, and listing both
            // would show every Mega twice.
            megasByDex = Dictionary(
                grouping: species.filter { $0.form.contains("Mega") && !$0.isShiny },
                by: { $0.dex })
            print("[pokedex] loaded \(species.count) species"
                  + (EmbeddedResources.isEmbedded ? " (embedded)" : " (from disk)"))
        } catch {
            print("[pokedex] failed to load: \(error.localizedDescription)")
        }
    }

    subscript(key: String) -> Species? { byKey[key] }

    /// Mega forms this species could turn into; empty if it has none, or if it
    /// is already a Mega. Champions adds its own beyond the mainline ones -
    /// "Mega Z" variants, and X/Y pairs for species that never had them - so
    /// this is read from the data rather than assumed.
    func megaForms(for species: Species) -> [Species] {
        guard !species.form.contains("Mega") else { return [] }
        return (megasByDex[species.dex] ?? []).sorted { $0.form < $1.form }
    }

    /// The Champions menu sprite for a species, decoded on first use.
    ///
    /// Locked because the cards read this on the main thread while the matcher
    /// may still be loading references on the analysis queue.
    func icon(for key: String) -> CGImage? {
        iconLock.lock()
        defer { iconLock.unlock() }
        if let cached = iconCache[key] { return cached }
        guard let data = EmbeddedResources.data("icons/\(key).png"),
              let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        iconCache[key] = cg
        return cg
    }
}
