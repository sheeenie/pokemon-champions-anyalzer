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
    private var loggedFrameSize = false

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
            print("[analyzer] capture frame size: \(Int(size.width))x\(Int(size.height))")
            if dumpDir == nil {
                print("[analyzer] set PKMN_DUMP_DIR to enable calibration dumps")
            }
        }

        if dumpDir != nil, now - lastDump >= dumpInterval, dumpCount < maxDumps {
            lastDump = now
            dump(pixelBuffer: pixelBuffer, size: size)
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
        let icons = BattleSlot.allCases.map { ($0, $0.iconRect(in: size)) }

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
