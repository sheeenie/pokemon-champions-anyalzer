import ScreenCaptureKit
import AVFoundation
import AppKit

/// The Android path: scrcpy puts the phone's screen in a window, and this reads
/// that window's pixels.
///
/// An iPhone offers its screen to macOS as a capture device, which is what the
/// AVFoundation path opens. Android offers nothing of the kind, so there is no
/// device to open. scrcpy mirrors the phone over adb into an ordinary window,
/// and macOS can read any window, so here the window is the camera.
///
/// Start scrcpy borderless, or the window's title bar arrives as part of the
/// picture and every calibrated region is off by its height:
///   scrcpy --window-borderless --no-audio --no-control
final class AndroidCapture: NSObject, SCStreamOutput {

    /// Frames, on `queue`.
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// Whether a phone is on screen, on the main queue. Carries the window's
    /// pixel size, which is the phone's screen shape.
    var onAvailability: ((CGSize?) -> Void)?

    /// The mirror draws straight from this, so a frame never has to be copied
    /// or converted just to be shown.
    let previewLayer = CALayer()

    private let queue = DispatchQueue(label: "io.github.sheeenie.pokemon-champions-analyzer.android")
    private var stream: SCStream?
    private var windowID: CGWindowID?
    private var pixelSize: CGSize = .zero
    private var timer: Timer?

    /// scrcpy's application name, which is how its window is recognised. The
    /// title is the user's to choose, so it cannot be the test.
    private static let appName = "scrcpy"

    override init() {
        super.init()
        previewLayer.contentsGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
    }

    /// False while an iPhone is attached: one source at a time, so the
    /// analyzer's state is only ever touched from one queue.
    var isEnabled = true {
        didSet { if !isEnabled { Task { await stop() } } }
    }
    /// Set when screen recording has not been granted, so the UI can offer to
    /// ask rather than a prompt appearing out of nowhere.
    var onPermissionNeeded: (() -> Void)?

    /// Watches for a scrcpy window, and keeps watching: the phone can be
    /// plugged in, mirrored, and unplugged while the app runs.
    func start() {
        guard permitted() else {
            Diagnostics.log("[android] screen recording not granted, so a "
                            + "scrcpy window cannot be read yet")
            DispatchQueue.main.async { self.onPermissionNeeded?() }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.look()
        }
        timer?.tolerance = 0.5
        look()
    }

    /// Reading another app's window needs screen recording, which is a
    /// different permission from the camera. This only checks: an iPhone user
    /// should never meet a prompt for a permission they do not need.
    private func permitted() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Asks for it, on the user's say-so. macOS grants it to the next launch,
    /// not this one, so this reports rather than pretends.
    func requestPermission() {
        Diagnostics.log("[android] asking for screen recording")
        if CGRequestScreenCaptureAccess() {
            start()
        } else {
            Diagnostics.log("[android] screen recording still not granted; "
                            + "allow it in System Settings, Privacy & Security, "
                            + "Screen Recording, then reopen the app")
        }
    }

    private func look() {
        Task { [weak self] in
            guard let self, self.isEnabled else { return }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true) else { return }

            // The largest scrcpy window, so a second mirror or a dialog does not
            // win over the phone.
            let window = content.windows
                .filter { $0.owningApplication?.applicationName == AndroidCapture.appName }
                .filter { $0.frame.width > 200 && $0.frame.height > 200 }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }

            guard let window else {
                await self.stop()
                return
            }
            let scale = NSScreen.screens.first { $0.frame.intersects(window.frame) }?
                .backingScaleFactor ?? 2
            let size = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
            // A resized window means a new stream: the configuration fixes the
            // frame size when capture starts.
            guard window.windowID != self.windowID || size != self.pixelSize else { return }
            await self.begin(window: window, size: size)
        }
    }

    private func begin(window: SCWindow, size: CGSize) async {
        await stop()

        let config = SCStreamConfiguration()
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // The analyzer wants four frames a second; ten keeps the mirror smooth
        // without spending more than that.
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        config.queueDepth = 3
        config.showsCursor = false
        config.scalesToFit = true

        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                              configuration: config, delegate: nil)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            Diagnostics.log("[android] could not read the scrcpy window: \(error.localizedDescription)")
            return
        }
        self.stream = stream
        windowID = window.windowID
        pixelSize = size
        Diagnostics.log("[android] mirroring scrcpy window \(Int(size.width))x\(Int(size.height))")
        await MainActor.run { self.onAvailability?(size) }
    }

    private func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        let had = windowID != nil
        windowID = nil
        pixelSize = .zero
        if had {
            Diagnostics.log("[android] scrcpy window gone")
            await MainActor.run { self.onAvailability?(nil) }
        }
    }

    // MARK: Frames

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, isEnabled,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Straight onto the layer: an IOSurface-backed buffer is something a
        // layer can show as it is.
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            DispatchQueue.main.async { [weak self] in
                self?.previewLayer.contents = surface
            }
        }

        // Called straight through on this queue, which is serial: with an
        // iPhone attached this source is disabled, so the analyzer is never
        // driven from two places at once.
        onFrame?(pixelBuffer)
    }
}
