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
}

/// Loads the generated reference data produced by tools/fetch_pokedex.py.
final class PokedexStore {
    static let shared = PokedexStore()

    private(set) var species: [Species] = []
    private var byKey: [String: Species] = [:]
    private var iconCache: [String: CGImage] = [:]
    private let resourceRoot: URL?

    init() {
        resourceRoot = PokedexStore.locateResources()
        load()
    }

    /// Prefers the app bundle, falling back to the source tree so the data can
    /// be exercised without a full build.
    private static func locateResources() -> URL? {
        if let dir = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: dir.appendingPathComponent("pokedex.json").path) {
            return dir
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: source.appendingPathComponent("pokedex.json").path) {
            return source
        }
        return nil
    }

    private func load() {
        guard let root = resourceRoot else {
            print("[pokedex] no pokedex.json found; run tools/fetch_pokedex.py")
            return
        }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("pokedex.json"))
            species = try JSONDecoder().decode([Species].self, from: data)
            byKey = Dictionary(uniqueKeysWithValues: species.map { ($0.key, $0) })
            print("[pokedex] loaded \(species.count) species")
        } catch {
            print("[pokedex] failed to load: \(error.localizedDescription)")
        }
    }

    subscript(key: String) -> Species? { byKey[key] }

    /// The Champions menu sprite for a species, decoded on first use.
    func icon(for key: String) -> CGImage? {
        if let cached = iconCache[key] { return cached }
        guard let root = resourceRoot else { return nil }
        let url = root.appendingPathComponent("icons/\(key).png")
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        iconCache[key] = cg
        return cg
    }
}
