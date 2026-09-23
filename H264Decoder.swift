import Foundation
import VideoToolbox
import CoreMedia

/// Turns the phone's H.264 stream into frames.
///
/// The stream arrives as Annex-B: parameter sets and pictures separated by
/// start codes, in whatever pieces the socket hands over, so this keeps a
/// remainder between reads rather than assuming a read ends on a boundary.
///
/// Rotating the phone restarts its encoder and sends new parameter sets, so a
/// change in those rebuilds the session: without that, turning the phone to
/// play would leave the decoder describing a screen shape that no longer
/// exists.
final class H264Decoder {

    /// The picture size, once the stream has said what it is.
    private(set) var size: CGSize?

    private let onImage: (CVPixelBuffer) -> Void
    private var remainder: [UInt8] = []
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    init(onImage: @escaping (CVPixelBuffer) -> Void) {
        self.onImage = onImage
    }

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    func feed(_ bytes: [UInt8]) {
        remainder.append(contentsOf: bytes)
        var units: [[UInt8]] = []

        // Everything up to the last start code is complete; the tail may not be.
        var starts: [(at: Int, header: Int)] = []
        var i = 0
        while i + 3 <= remainder.count {
            if remainder[i] == 0, remainder[i + 1] == 0, remainder[i + 2] == 1 {
                starts.append((i + 3, 3)); i += 3
            } else if i + 4 <= remainder.count, remainder[i] == 0, remainder[i + 1] == 0,
                      remainder[i + 2] == 0, remainder[i + 3] == 1 {
                starts.append((i + 4, 4)); i += 4
            } else {
                i += 1
            }
        }
        guard starts.count > 1 else { return }
        for n in 0..<(starts.count - 1) {
            let from = starts[n].at
            let to = starts[n + 1].at - starts[n + 1].header
            if to > from { units.append(Array(remainder[from..<to])) }
        }
        remainder = Array(remainder[(starts[starts.count - 1].at - starts[starts.count - 1].header)...])

        for unit in units { handle(unit) }
    }

    private func handle(_ unit: [UInt8]) {
        guard let first = unit.first else { return }
        switch first & 0x1F {
        case 7:
            if sps != unit { sps = unit; rebuild() }
        case 8:
            if pps != unit { pps = unit; rebuild() }
        case 1, 5:
            decode(unit)
        default:
            break
        }
    }

    private func rebuild() {
        guard let sps, let pps else { return }
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        format = nil

        var built: CMVideoFormatDescription?
        sps.withUnsafeBufferPointer { s in
            pps.withUnsafeBufferPointer { p in
                let pointers = [s.baseAddress!, p.baseAddress!]
                let sizes = [s.count, p.count]
                pointers.withUnsafeBufferPointer { ptr in
                    sizes.withUnsafeBufferPointer { sz in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: ptr.baseAddress!,
                            parameterSetSizes: sz.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &built)
                    }
                }
            }
        }
        guard let built else { return }
        format = built
        let dimensions = CMVideoFormatDescriptionGetDimensions(built)
        size = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))

        var record = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, image, _, _ in
                guard status == noErr, let image, let refcon else { return }
                let decoder = Unmanaged<H264Decoder>.fromOpaque(refcon).takeUnretainedValue()
                decoder.onImage(image)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            // The analyzer reads these on the CPU, and the mirror shows them.
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var created: VTDecompressionSession?
        VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                     formatDescription: built,
                                     decoderSpecification: nil,
                                     imageBufferAttributes: attributes as CFDictionary,
                                     outputCallback: &record,
                                     decompressionSessionOut: &created)
        session = created
    }

    private func decode(_ unit: [UInt8]) {
        guard let session, let format else { return }

        // VideoToolbox wants each picture prefixed with its length, where the
        // stream has a start code.
        var framed = [UInt8]()
        framed.reserveCapacity(unit.count + 4)
        var length = UInt32(unit.count).bigEndian
        withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
        framed.append(contentsOf: unit)
        let total = framed.count

        var block: CMBlockBuffer?
        let made = framed.withUnsafeMutableBytes { raw -> Bool in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: raw.baseAddress,
                blockLength: total,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: total,
                flags: 0,
                blockBufferOut: &block) == noErr
        }
        guard made, let block else { return }

        var sample: CMSampleBuffer?
        var sampleSize = total
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                        dataBuffer: block,
                                        formatDescription: format,
                                        sampleCount: 1,
                                        sampleTimingEntryCount: 0,
                                        sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1,
                                        sampleSizeArray: &sampleSize,
                                        sampleBufferOut: &sample) == noErr,
              let sample else { return }

        // Synchronous: the bytes above live only as long as this call.
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample,
                                          flags: [], frameRefcon: nil, infoFlagsOut: nil)
    }
}
