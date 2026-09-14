import Foundation
import MachO

/// The app's resources (sprites, type icons, pokedex.json), linked into the
/// executable by build.sh so the app works as a single download.
///
/// build.sh packs Resources/ with tools/pack_resources.py and links the result
/// into a section of the executable. When that section is absent - for example
/// in tools that compile these sources on their own - this falls back to a
/// Resources folder on disk.
enum EmbeddedResources {
    static let segment = "__TEXT"
    static let section = "__resources"

    private struct Entry {
        let offset: Int
        let length: Int
    }

    private static let blob: (data: Data, index: [String: Entry])? = {
        var size: UInt = 0
        // #dsohandle is the image this code is linked into: the app executable.
        let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
        guard let start = getsectiondata(header, segment, section, &size), size > 12 else {
            return nil
        }
        // Points into the mapped executable, which lives as long as the process.
        let data = Data(bytesNoCopy: start, count: Int(size), deallocator: .none)
        guard let index = parse(data) else {
            print("[resources] embedded section is present but malformed")
            return nil
        }
        return (data, index)
    }()

    /// Whether this build carries its resources inside the executable.
    static var isEmbedded: Bool { blob != nil }

    /// A resource by its path under Resources/, e.g. "icons/garchomp.png".
    static func data(_ path: String) -> Data? {
        if let blob, let entry = blob.index[path] {
            return blob.data.subdata(in: entry.offset..<entry.offset + entry.length)
        }
        guard let root = diskRoot else { return nil }
        return try? Data(contentsOf: root.appendingPathComponent(path))
    }

    /// Resources folder in the app bundle, else the one next to these sources.
    private static let diskRoot: URL? = {
        let marker = "pokedex.json"
        if let dir = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) {
            return dir
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        return FileManager.default.fileExists(atPath: source.appendingPathComponent(marker).path)
            ? source : nil
    }()

    /// Reads the index written by tools/pack_resources.py.
    private static func parse(_ data: Data) -> [String: Entry]? {
        func u32(_ at: Int) -> Int {
            Int(UInt32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) }))
        }
        func u64(_ at: Int) -> Int {
            Int(UInt64(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt64.self) }))
        }
        guard data.count >= 12, data.prefix(4) == Data("PKRS".utf8), u32(4) == 1 else { return nil }

        var index: [String: Entry] = [:]
        var cursor = 12
        for _ in 0..<u32(8) {
            guard cursor + 4 <= data.count else { return nil }
            let length = u32(cursor)
            cursor += 4
            guard cursor + length + 16 <= data.count,
                  let path = String(data: data.subdata(in: cursor..<cursor + length), encoding: .utf8)
            else { return nil }
            cursor += length
            let offset = u64(cursor), size = u64(cursor + 8)
            cursor += 16
            guard offset + size <= data.count else { return nil }
            index[path] = Entry(offset: offset, length: size)
        }
        return index
    }
}
