import Foundation

/// One move a Pokemon is known to carry, with how often it is seen.
struct UsageMove: Codable {
    let name: String
    let pct: Double?
}

private struct UsageEntry: Codable {
    let id: String
    /// Kept apart because they are different games: a Pokemon's doubles set is
    /// not its singles set. Garchomp runs Dragon Claw in one and not the other.
    let singles: [UsageMove]
    let doubles: [UsageMove]

    func moves(_ format: BattleFormat) -> [UsageMove] {
        let wanted = format == .doubles ? doubles : singles
        // A Pokemon seen in only one format still gets an answer, since the
        // other format's set is a better guess than no moves at all.
        return wanted.isEmpty ? (format == .doubles ? singles : doubles) : wanted
    }
}

private struct UsageFile: Codable {
    let generated: String?
    let pokemon: [String: UsageEntry]
}

/// Which moves each Pokemon actually carries, from championsbattledata.com.
///
/// A snapshot is built into the app so it works offline on first launch, and
/// each Pokemon is refreshed from the API the first time it is seen in a
/// battle - the meta shifts, and a snapshot frozen at release time slowly stops
/// describing the game. A refresh that fails changes nothing: the snapshot
/// stays, which is the whole reason for shipping one.
final class UsageStore {
    static let shared = UsageStore()

    private static let api = "https://championsbattledata.com/api/battle/"
    /// How long a downloaded copy is trusted before being fetched again. The
    /// site publishes daily, so anything shorter is just load on their server.
    private static let freshness: TimeInterval = 24 * 60 * 60

    private let queue = DispatchQueue(label: "usage.store")
    private var entries: [String: UsageEntry] = [:]
    private var moveData: [String: MoveData] = [:]
    private var refreshed: Set<String> = []
    private var loaded = false

    /// Downloaded copies live here, outside the app bundle, so a refresh
    /// survives relaunches without the app rewriting its own signed contents.
    private let cacheDir: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("PokemonChampionsAnalyzer/usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Loading

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        if let data = EmbeddedResources.data("usage.json"),
           let file = try? JSONDecoder().decode(UsageFile.self, from: data) {
            entries = file.pokemon
        } else {
            print("[usage] no usage.json found; run tools/fetch_usage.py")
        }
        if let data = EmbeddedResources.data("moves.json"),
           let moves = try? JSONDecoder().decode([String: MoveData].self, from: data) {
            moveData = moves
        }
        print("[usage] \(entries.count) Pokemon, \(moveData.count) moves")
    }

    /// The species key a usage entry is filed under. Shiny artwork and Mega
    /// forms are the same Pokemon as far as the team-building data goes, and
    /// only the base form has its own entry.
    private func baseKey(_ key: String) -> String {
        var k = key
        for suffix in ["-shiny", "-mega-x", "-mega-y", "-mega-z", "-mega"] {
            if k.hasSuffix(suffix) { k = String(k.dropLast(suffix.count)) }
        }
        return k
    }

    /// The key this species' usage is filed under, or nil when there is none.
    ///
    /// Trimming the suffix is not enough on its own: a Mega's key does not
    /// always contain its base form's key. Floette Eternal Flower is
    /// "floette-eternal" while its Mega is "floette-mega", so trimming asks for
    /// a "floette" that no entry uses, and the card silently lost its damage
    /// estimates the moment it Mega Evolved. The dex number identifies the base
    /// exactly, so it is the fallback - and only a fallback, because species
    /// that share a dex with a different usage entry, such as Indeedee and
    /// Indeedee-F, must keep resolving to their own.
    ///
    /// Call on `queue`.
    private func usageKey(for species: Species) -> String? {
        let trimmed = baseKey(species.key)
        if entries[trimmed] != nil { return trimmed }
        for candidate in PokedexStore.shared.species
        where candidate.dex == species.dex
            && !candidate.isShiny
            && !candidate.form.contains("Mega") {
            if entries[candidate.key] != nil { return candidate.key }
        }
        return nil
    }

    // MARK: Lookup

    func moves(for species: Species, format: BattleFormat) -> [UsageMove] {
        queue.sync {
            loadIfNeeded()
            guard let key = usageKey(for: species) else { return [] }
            return entries[key]?.moves(format) ?? []
        }
    }

    func move(_ name: String) -> MoveData? {
        queue.sync {
            loadIfNeeded()
            return moveData[name]
        }
    }

    // MARK: Refresh

    /// Brings one Pokemon's moves up to date, at most once per session and at
    /// most once a day on disk. Safe to call from the analysis queue: the
    /// network work happens elsewhere and the result is merged back here.
    func refresh(_ species: Species, format: BattleFormat) {
        guard format != .idle else { return }
        let path = format == .doubles ? "Doubles" : "Singles"
        queue.async {
            self.loadIfNeeded()
            guard let base = self.usageKey(for: species),
                  let id = self.entries[base]?.id,
                  !self.refreshed.contains("\(id)/\(path)") else { return }
            self.refreshed.insert("\(id)/\(path)")

            if let cached = self.cacheDir?.appendingPathComponent("\(id)-\(path).json"),
               let attrs = try? FileManager.default.attributesOfItem(atPath: cached.path),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < UsageStore.freshness,
               let data = try? Data(contentsOf: cached) {
                self.merge(id: id, base: base, format: format, data: data)
                return
            }
            self.download(id: id, base: base, format: format, path: path)
        }
    }

    private func download(id: String, base: String, format: BattleFormat, path: String) {
        guard let url = URL(string: UsageStore.api + path + "/" + id) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  let data,
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            self.queue.async {
                self.merge(id: id, base: base, format: format, data: data)
                if let cached = self.cacheDir?.appendingPathComponent("\(id)-\(path).json") {
                    try? data.write(to: cached)
                }
            }
        }.resume()
    }

    /// Replaces one Pokemon's move list from an API response. Rows come from
    /// the network, so anything unexpected is dropped rather than trusted.
    private func merge(id: String, base: String, format: BattleFormat, data: Data) {
        struct Row: Codable {
            let category: String?
            let rank: Int?
            let name: String?
            let percentage_value: Double?
        }
        struct Response: Codable { let rows: [Row]? }

        guard let rows = (try? JSONDecoder().decode(Response.self, from: data))?.rows else { return }
        let moves = rows
            .filter { $0.category == "move" }
            .sorted { ($0.rank ?? 99) < ($1.rank ?? 99) }
            .compactMap { row -> UsageMove? in
                guard let name = row.name, !name.isEmpty else { return nil }
                return UsageMove(name: name, pct: row.percentage_value)
            }
        guard !moves.isEmpty, let existing = entries[base] else { return }
        entries[base] = UsageEntry(id: id,
                                   singles: format == .doubles ? existing.singles : moves,
                                   doubles: format == .doubles ? moves : existing.doubles)
    }
}
