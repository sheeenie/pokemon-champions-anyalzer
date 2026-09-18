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
    let queue = DispatchQueue(label: "io.github.sheeenie.pokemon-champions-analyzer.analysis")

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

    /// Below this, the screen counts as black, which is where the loading-screen
    /// check below runs. Recognising a loading screen arms a reset that the next
    /// detected Pokemon carries out.
    private static let blackThreshold = 0.03

    /// A black screen alone does not mean a battle ended: the screen also goes
    /// dark during move animations and camera cuts, and those were clearing the
    /// panel mid-battle. The loading screen between battles is the one showing a
    /// Rotom icon over a progress bar in the bottom-right corner, so that icon,
    /// not the darkness, is what arms the reset.
    ///
    /// Measured on a recorded loading screen: the icon lights 3.0% of this box
    /// above the cut, and a mid-battle fade lights none of it. Averaging would
    /// not separate them - the fade's mean corner brightness (0.022) is higher
    /// than the loading screen's (0.015), because the fade is dim everywhere
    /// while the loading screen is black with a few bright pixels. Hence a
    /// count of bright pixels. Below a cut of 0.235 the fade's noise starts
    /// counting too, so that is the separating value rather than a free choice.
    /// Where to look is the device profile's `loadingIconBox`.
    private static let loadingIconLuma = 0.235
    private static let loadingIconCoverage = 0.008

    /// Fallback for a device or update whose loading icon this misses: a screen
    /// black this long is not a move animation, so end the battle anyway.
    private static let blackFramesToReset = 32   // ~8s at the analysis cadence

    /// Where to look on this phone's screen, chosen from the frame's shape the
    /// first time a landscape frame arrives, and again if that shape changes.
    private var profile = CaptureProfile.iPhone17
    private var profileFrameSize: CGSize = .zero

    private var blackFrames = 0
    /// One reset per black stretch, however long it lasts.
    private var armedThisStretch = false

    private var blackDumpCount = 0
    private let maxBlackDumps = 40
    /// Frames to save per black stretch: a few examples of several stretches,
    /// not every frame of the first one.
    private let blackDumpsPerStretch = 4

    init(tracker: BattleStateTracker) {
        self.tracker = tracker
        super.init()
    }

    /// Analysis cadence. Capture runs at display rate; we only need a few Hz.
    private let analysisInterval: TimeInterval = 0.25
    private var lastAnalysis: TimeInterval = 0

    // MARK: Calibration dumping

    /// Enable calibration dumps with:
    ///   defaults write io.github.sheeenie.pokemon-champions-analyzer dumpDir -string /some/dir
    ///
    /// Read from UserDefaults rather than the environment because the app must be
    /// launched via `open` to retain its screen-capture permission; a binary run
    /// straight from a shell captures only black frames.
    private var dumpDir: URL? { Diagnostics.dumpDir }
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
    private func log(_ message: String) { Diagnostics.log(message) }

    /// Identify each slot's occupant, skipping slots whose artwork is unchanged.
    private func identify(in pixelBuffer: CVPixelBuffer, size: CGSize) {
        // The game only runs landscape. A portrait frame is the lock screen,
        // home screen, or a rotation - not a battle - and every calibrated box
        // would be pointing at unrelated pixels, which can produce confident
        // nonsense. Report the field as empty instead.
        // Cards deliberately persist, so leaving the game does not wipe the
        // panel; only a new identification replaces one.
        guard size.width > size.height else {
            if !lastSignature.isEmpty {
                lastSignature.removeAll()
                lastResult.removeAll()
                log("[analyzer] portrait frame (\(Int(size.width))x\(Int(size.height))): not a battle")
            }
            return
        }

        if size != profileFrameSize {
            profileFrameSize = size
            profile = CaptureProfile.matching(size)
            log("[analyzer] capture profile: \(profile.name), measured at "
                + "\(Int(profile.frameSize.width))x\(Int(profile.frameSize.height))")
        }

        guard let frame = makeCGImage(from: pixelBuffer) else { return }

        let brightness = meanBrightness(of: frame)
        if brightness < BattleAnalyzer.blackThreshold {
            blackFrames += 1
            let coverage = litCoverage(of: frame, region: profile.loadingIconBox)
            let loading = coverage >= BattleAnalyzer.loadingIconCoverage
            // The icon fades in a little after the screen goes black, so this
            // waits for it rather than deciding on the first black frame.
            if !armedThisStretch, loading || blackFrames >= BattleAnalyzer.blackFramesToReset {
                armedThisStretch = true
                tracker.armReset()
                log(String(format: "[analyzer] loading screen (brightness %.4f, icon %.2f%%%@): reset armed",
                           brightness, coverage * 100, loading ? "" : ", on duration"))
            }
            captureBlackFrame(frame, brightness: brightness, coverage: coverage)
            return
        }
        blackFrames = 0
        armedThisStretch = false

        for slot in BattleSlot.allCases {
            let rect = profile.spriteRect(slot, in: size)
            guard let crop = frame.cropping(to: rect),
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
            let result = matcher.match(in: frame, near: rect)
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

    /// Saves black frames, which the normal dump skips: this is the only way to
    /// see why a loading screen was or wasn't recognised on another device.
    private func captureBlackFrame(_ frame: CGImage, brightness: Double, coverage: Double) {
        guard let dir = dumpDir, blackDumpCount < maxBlackDumps,
              blackFrames <= blackDumpsPerStretch else { return }
        let index = blackDumpCount
        blackDumpCount += 1
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        write(frame, to: dir.appendingPathComponent("black\(index)-full.png"))
        let size = CGSize(width: frame.width, height: frame.height)
        let box = profile.loadingIconBox
        let rect = CGRect(x: box.minX * size.width, y: box.minY * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        if let crop = frame.cropping(to: rect) {
            write(crop, to: dir.appendingPathComponent("black\(index)-corner.png"))
        }
        log(String(format: "[analyzer] saved black frame %d (brightness %.4f, icon %.2f%%)",
                   index, brightness, coverage * 100))
    }

    /// Mean brightness of the whole frame, 0...1. Detects black screens (end of
    /// a battle, phone asleep) and keeps blank frames out of calibration dumps.
    ///
    /// Averages a 32x16 downsample. Drawing straight into a single pixel with low
    /// interpolation samples only a few source pixels, which is unreliable for a
    /// decision that clears the speed list.
    private func meanBrightness(of image: CGImage) -> Double {
        let w = 32, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])
        }
        return sum / (Double(w * h) * 3 * 255)
    }

    /// Fraction of a region's pixels brighter than `loadingIconLuma`, 0...1.
    ///
    /// Sampled at 128x96, about the resolution this was calibrated at, which
    /// keeps the cost negligible. The icon is a few hundred pixels across in a
    /// full frame, so it survives the downsample: it measures 3.0% here against
    /// a threshold of 0.8%.
    private func litCoverage(of image: CGImage, region: CGRect) -> Double {
        let rect = CGRect(x: region.minX * CGFloat(image.width),
                          y: region.minY * CGFloat(image.height),
                          width: region.width * CGFloat(image.width),
                          height: region.height * CGFloat(image.height))
        guard let crop = image.cropping(to: rect) else { return 0 }

        let w = 128, h = 96
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))

        var lit = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let luma = 0.299 * Double(pixels[i])
                + 0.587 * Double(pixels[i + 1])
                + 0.114 * Double(pixels[i + 2])
            if luma / 255 > BattleAnalyzer.loadingIconLuma { lit += 1 }
        }
        return Double(lit) / Double(w * h)
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

        let plates = BattleSlot.allCases.map { ($0, profile.plateRect($0, in: size)) }
        let icons = BattleSlot.allCases.map { ($0, profile.spriteRect($0, in: size)) }

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
