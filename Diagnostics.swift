import Foundation

/// Where diagnostics go, and how to write them.
///
/// The app has to be launched with `open` to keep its screen-capture
/// permission, and that discards stdout, so a file is the only way to see what
/// happened. Shared by the capture session and the analyzer, because the first
/// question about an empty panel is always which of the two stopped.
enum Diagnostics {

    /// Enable with:
    ///   defaults write io.github.sheeenie.pokemon-champions-analyzer dumpDir -string ~/Desktop/pokemon-debug
    static let dumpDir: URL? = {
        let raw = UserDefaults.standard.string(forKey: "dumpDir")
            ?? ProcessInfo.processInfo.environment["PKMN_DUMP_DIR"]
        return raw.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }()

    static func log(_ message: String) {
        print(message)
        guard let dir = dumpDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = message + "\n"
        let url = dir.appendingPathComponent("analyzer.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
