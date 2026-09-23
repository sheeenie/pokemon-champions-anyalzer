import Foundation
import AVFoundation
import VideoToolbox
import AppKit

/// Reads an Android phone's screen directly, the way scrcpy does.
///
/// An iPhone offers its screen to macOS as a capture device. Android offers
/// nothing of the kind, so this does what scrcpy's own client does: push
/// scrcpy's server onto the phone over adb, start it, and read the H.264 stream
/// it sends back through a forwarded socket.
///
/// The alternative was to let scrcpy draw a window and photograph that, which
/// worked but asked the user to keep a window open and to grant macOS's screen
/// recording permission - a permission for reading *other* apps, which this app
/// has no other use for. Speaking the protocol costs a decoder and buys both
/// back.
///
/// The server is scrcpy's, shipped inside this app so its version always
/// matches the protocol below. scrcpy is Apache 2.0; see the README.
final class AndroidDirect {

    /// Frames, on `queue`.
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// The phone's screen size when one is streaming, nil when none is.
    var onAvailability: ((CGSize?) -> Void)?
    /// Something a person should know: no adb, no phone, debugging refused.
    var onStatus: ((String?) -> Void)?

    /// The mirror draws from this, so a frame is never copied to be shown.
    let previewLayer = CALayer()

    /// False while an iPhone is attached: one source at a time.
    var isEnabled = true {
        didSet { if !isEnabled { stopSession() } }
    }

    /// The protocol this speaks, and the version the bundled server checks for.
    private static let serverVersion = "4.1"
    /// Nothing else is listening here, and it is released when the app exits.
    private static let port: UInt16 = 27183

    private let queue = DispatchQueue(label: "io.github.sheeenie.pokemon-champions-analyzer.android")
    private var timer: Timer?
    private var server: Process?
    private var socket: Int32 = -1
    private var reader: Thread?
    private var decoder: H264Decoder?
    private var streaming = false
    private var reportedNoAdb = false
    private var reportedNoDevice = false

    // MARK: Looking for a phone

    /// Watches for a phone, and keeps watching: one can be plugged in, unlocked
    /// and unplugged while the app runs.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.look()
        }
        timer?.tolerance = 1
        look()
    }

    private func look() {
        guard isEnabled, !streaming else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard let adb = AndroidDirect.adbPath() else {
                if !self.reportedNoAdb {
                    self.reportedNoAdb = true
                    Diagnostics.log("[android] adb not found; install it with "
                                    + "brew install --cask android-platform-tools")
                    DispatchQueue.main.async { self.onStatus?("Android needs adb") }
                }
                return
            }
            self.reportedNoAdb = false

            let listed = AndroidDirect.run(adb, ["devices"])?
                .split(separator: "\n").dropFirst()
                .map { $0.split(separator: "\t", omittingEmptySubsequences: true) }
                .filter { $0.count >= 2 } ?? []

            guard let device = listed.first(where: { $0[1].trimmingCharacters(in: .whitespaces) == "device" }) else {
                let unauthorized = listed.contains { $0[1].hasPrefix("unauthorized") }
                if unauthorized {
                    Diagnostics.log("[android] phone found but USB debugging is not allowed yet; "
                                    + "tap Allow on the phone")
                    DispatchQueue.main.async { self.onStatus?("Allow USB debugging on the phone") }
                } else if !self.reportedNoDevice {
                    self.reportedNoDevice = true
                    Diagnostics.log("[android] no Android phone with USB debugging")
                }
                return
            }
            self.reportedNoDevice = false
            self.startSession(adb: adb, serial: String(device[0]))
        }
    }

    // MARK: One streaming session

    private func startSession(adb: String, serial: String) {
        guard let serverData = EmbeddedResources.data("scrcpy-server") else {
            Diagnostics.log("[android] the bundled scrcpy server is missing from this build")
            return
        }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("scrcpy-server.jar")
        do { try serverData.write(to: local) } catch {
            Diagnostics.log("[android] could not unpack the server: \(error.localizedDescription)")
            return
        }

        // scrcpy deletes the server from the phone when it exits, so this is
        // pushed every time rather than assumed to be there.
        guard AndroidDirect.run(adb, ["-s", serial, "push", local.path,
                                      "/data/local/tmp/scrcpy-server.jar"]) != nil else {
            Diagnostics.log("[android] could not copy the server to the phone")
            return
        }

        let scid = String(format: "%08x", UInt32.random(in: 0...0x7FFF_FFFF))
        _ = AndroidDirect.run(adb, ["-s", serial, "forward", "--remove",
                                    "tcp:\(AndroidDirect.port)"])
        guard AndroidDirect.run(adb, ["-s", serial, "forward",
                                      "tcp:\(AndroidDirect.port)",
                                      "localabstract:scrcpy_\(scid)"]) != nil else {
            Diagnostics.log("[android] could not forward the phone's socket")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["-s", serial, "shell",
                             "CLASSPATH=/data/local/tmp/scrcpy-server.jar",
                             "app_process", "/", "com.genymobile.scrcpy.Server",
                             AndroidDirect.serverVersion,
                             "scid=\(scid)",
                             "log_level=error",
                             "video=true", "audio=false", "control=false",
                             "tunnel_forward=true",
                             // No framing, no metadata: just the encoded video.
                             "raw_stream=true",
                             // Full screen resolution: the sprite the matcher
                             // reads is about a tenth of the frame's height.
                             "max_size=0",
                             "video_codec=h264"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Diagnostics.log("[android] could not start the server: \(error.localizedDescription)")
            return
        }
        server = process
        streaming = true
        Diagnostics.log("[android] started the phone's screen server")

        let thread = Thread { [weak self] in self?.readStream() }
        thread.name = "android.stream"
        reader = thread
        thread.start()
    }

    /// Connects and reads until the stream ends.
    ///
    /// The connection is retried because adb accepts the local port before the
    /// phone is listening behind it, and hands back a socket that closes at
    /// once: connecting too early looks like success and yields nothing.
    private func readStream() {
        let decoder = H264Decoder { [weak self] image in
            guard let self, self.isEnabled else { return }
            if let surface = CVPixelBufferGetIOSurface(image)?.takeUnretainedValue() {
                DispatchQueue.main.async { self.previewLayer.contents = surface }
            }
            self.onFrame?(image)
        }
        self.decoder = decoder

        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        let giveUp = Date().addingTimeInterval(20)
        var announced = false

        while streaming, Date() < giveUp {
            let fd = AndroidDirect.connect(port: AndroidDirect.port)
            guard fd >= 0 else { Thread.sleep(forTimeInterval: 0.4); continue }
            socket = fd

            var got = 0
            while streaming {
                let n = read(fd, &buffer, buffer.count)
                if n <= 0 { break }
                got += n
                decoder.feed(Array(buffer[0..<n]))
                if !announced, let size = decoder.size {
                    announced = true
                    Diagnostics.log("[android] streaming \(Int(size.width))x\(Int(size.height)) from the phone")
                    DispatchQueue.main.async {
                        self.onAvailability?(size)
                        self.onStatus?(nil)
                    }
                }
            }
            close(fd)
            socket = -1
            if got > 0 { break }        // the stream ended rather than never starting
            Thread.sleep(forTimeInterval: 0.4)
        }

        if streaming { stopSession() }
    }

    private func stopSession() {
        guard streaming || server != nil else { return }
        streaming = false
        if socket >= 0 { close(socket); socket = -1 }
        server?.terminate()
        server = nil
        decoder = nil
        Diagnostics.log("[android] the phone's screen stopped")
        DispatchQueue.main.async { self.onAvailability?(nil) }
    }

    // MARK: Small helpers

    /// A GUI app inherits none of a shell's PATH, so adb is looked for where it
    /// actually installs.
    private static func adbPath() -> String? {
        let candidates = ["/opt/homebrew/bin/adb",
                          "/usr/local/bin/adb",
                          NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func connect(port: UInt16) -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        if !ok { close(fd); return -1 }
        return fd
    }
}
