import Foundation
import AVFoundation
import AppKit
import CoreImage

/// Receives capture frames and (for now) dumps annotated calibration images.
///
/// Frame callbacks arrive on `queue` and must never block: the capture output is
/// configured to discard late frames, and analysis is throttled well below the
/// capture rate.
final class BattleAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Serial queue the capture output delivers frames on.
    let queue = DispatchQueue(label: "com.example.iPhoneMirror.analysis")

    private let ciContext = CIContext()
    private let tracker: BattleStateTracker
    private let matcher = IconMatcher()
    private var loggedFrameSize = false

    /// Last fingerprint per slot, so the library search runs only on change.
    private var lastSignature: [BattleSlot: [UInt8]] = [:]
    /// Last match per slot, replayed on unchanged frames. The tracker debounces
    /// by counting agreeing observations, so it must be fed every frame -
    /// otherwise skipping unchanged frames starves it and it never commits.
    private var lastResult: [BattleSlot: MatchResult] = [:]

    init(tracker: BattleStateTracker) {
        self.tracker = tracker
        super.init()
    }

    /// Analysis cadence. Capture runs at display rate; we only need a few Hz.
    private let analysisInterval: TimeInterval = 0.25
    private var lastAnalysis: TimeInterval = 0

    // MARK: Calibration dumping

    /// Enable calibration dumps with:
    ///   defaults write com.example.iPhoneMirror dumpDir -string /some/dir
    ///
    /// Read from UserDefaults rather than the environment because the app must be
    /// launched via `open` to retain its screen-capture permission; a binary run
    /// straight from a shell captures only black frames.
    private let dumpDir: URL? = {
        let raw = UserDefaults.standard.string(forKey: "dumpDir")
            ?? ProcessInfo.processInfo.environment["PKMN_DUMP_DIR"]
        return raw.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }()
    private let dumpInterval: TimeInterval = 3.0
    private let maxDumps = 20
    private var lastDump: TimeInterval = 0
    private var dumpCount = 0

    // MARK: Frame delivery

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= analysisInterval else { return }
        lastAnalysis = now

        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        if !loggedFrameSize {
            loggedFrameSize = true
            log("[analyzer] capture frame size: \(Int(size.width))x\(Int(size.height))")
            if dumpDir == nil {
                print("[analyzer] set the dumpDir default to enable calibration dumps")
            }
        }

        // Built on first frame, on this queue: it decodes 393 icons, which has
        // no business running during SwiftUI view construction.
        if !matcher.isReady {
            matcher.prepare(from: PokedexStore.shared)
            log("[analyzer] matcher ready")
        }
        identify(in: pixelBuffer, size: size)

        if dumpDir != nil, now - lastDump >= dumpInterval, dumpCount < maxDumps {
            lastDump = now
            dump(pixelBuffer: pixelBuffer, size: size)
        }
    }

    /// Print, and also append to a file when dumping is on. The app has to be
    /// launched via `open` to keep its screen-capture permission, and that
    /// discards stdout, so a file is the only way to see diagnostics.
    private func log(_ message: String) {
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

    /// Identify each slot's occupant, skipping slots whose artwork is unchanged.
    private func identify(in pixelBuffer: CVPixelBuffer, size: CGSize) {
        // The game only runs landscape. A portrait frame is the lock screen,
        // home screen, or a rotation - not a battle - and every calibrated box
        // would be pointing at unrelated pixels, which can produce confident
        // nonsense. Report the field as empty instead.
        guard size.width > size.height else {
            if !lastSignature.isEmpty {
                lastSignature.removeAll()
                lastResult.removeAll()
                log("[analyzer] portrait frame (\(Int(size.width))x\(Int(size.height))): not a battle")
            }
            for slot in BattleSlot.allCases { tracker.observe(slot, nil) }
            return
        }

        guard let frame = makeCGImage(from: pixelBuffer) else { return }

        for slot in BattleSlot.allCases {
            guard let crop = frame.cropping(to: slot.spriteRect(in: size)),
                  let signature = IconMatcher.signature(crop)
            else { continue }

            let unchanged = lastSignature[slot].map { !IconMatcher.differs($0, signature) } ?? false
            if unchanged {
                // Replay the cached answer: cheap, and keeps the debounce fed.
                tracker.observe(slot, lastResult[slot])
                continue
            }
            lastSignature[slot] = signature

            let previousKey = lastResult[slot]?.species.key
            let result = matcher.match(crop)
            if let result {
                lastResult[slot] = result
            } else {
                lastResult.removeValue(forKey: slot)
            }
            tracker.observe(slot, result)

            // Only log transitions; a slot over the moving battlefield changes
            // every frame and would otherwise flood the log.
            guard result?.species.key != previousKey else { continue }
            if let result {
                log(String(format: "[match] %@ -> %@ (d %.4f, margin %.2fx)",
                           slot.label, result.species.name, result.distance, result.margin))
            } else {
                log("[match] \(slot.label) -> unidentified")
            }
        }
    }

    /// Mean brightness, via a 1x1 downsample. Used to skip blank frames (phone
    /// asleep, transitions) so calibration dumps capture actual gameplay.
    private func meanBrightness(of image: CGImage) -> Double {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(data: &pixel,
                                  width: 1,
                                  height: 1,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }

    // MARK: Calibration output

    private func dump(pixelBuffer: CVPixelBuffer, size: CGSize) {
        guard let dir = dumpDir, let full = makeCGImage(from: pixelBuffer) else { return }

        let brightness = meanBrightness(of: full)
        guard brightness > 0.04 else {
            print("[analyzer] skipping blank frame (brightness \(String(format: "%.3f", brightness)))")
            return
        }

        let index = dumpCount
        dumpCount += 1

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[analyzer] cannot create dump dir: \(error.localizedDescription)")
            return
        }

        let plates = BattleSlot.allCases.map { ($0, $0.plateRect(in: size)) }
        let icons = BattleSlot.allCases.map { ($0, $0.spriteRect(in: size)) }

        if let annotated = annotate(full, rects: (plates + icons).map { $0.1 }) {
            write(annotated, to: dir.appendingPathComponent("frame\(index)-annotated.png"))
        }
        write(full, to: dir.appendingPathComponent("frame\(index)-full.png"))

        for (slot, rect) in plates {
            guard let crop = full.cropping(to: rect) else { continue }
            write(crop, to: dir.appendingPathComponent("frame\(index)-\(slot.label).png"))
        }
        for (slot, rect) in icons {
            guard let crop = full.cropping(to: rect) else { continue }
            write(crop, to: dir.appendingPathComponent("frame\(index)-\(slot.label)-icon.png"))
        }

        print("[analyzer] dumped frame \(index) to \(dir.path)")
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    /// Strokes the plate ROIs onto a copy of the frame so alignment can be eyeballed.
    private func annotate(_ image: CGImage, rects: [CGRect]) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setLineWidth(max(2, CGFloat(w) / 400))
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))

        // CGContext is bottom-left origin; plate rects are top-left.
        for r in rects {
            ctx.stroke(CGRect(x: r.origin.x,
                              y: CGFloat(h) - r.origin.y - r.height,
                              width: r.width,
                              height: r.height))
        }
        return ctx.makeImage()
    }

    private func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
