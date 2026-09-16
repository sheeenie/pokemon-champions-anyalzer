import SwiftUI
import AppKit
import CoreGraphics

/// Type colours, taken from the 52poke wiki palette.
enum TypePalette {
    private static let hex: [String: UInt32] = [
        "normal": 0xBBBBAA, "fire": 0xFF4422, "water": 0x3399FF,
        "electric": 0xFFCC33, "grass": 0x77CC55, "ice": 0x77DDFF,
        "fighting": 0xBB5544, "poison": 0xAA5599, "ground": 0xDDBB55,
        "flying": 0x6699FF, "psychic": 0xFF5599, "bug": 0xAABB22,
        "rock": 0xBBAA66, "ghost": 0x6666BB, "dragon": 0x7766EE,
        "dark": 0x775544, "steel": 0xAAAABB, "fairy": 0xFFAAFF,
    ]

    /// Darker variants, used where a chip needs to sit against the light one.
    private static let hexDark: [String: UInt32] = [
        "normal": 0x8A8A7B, "fire": 0xBA1F00, "water": 0x0D6AC8,
        "electric": 0xBD8E00, "grass": 0x40C60A, "ice": 0x13A8D9,
        "fighting": 0x912E1E, "poison": 0x792F6A, "ground": 0xB59226,
        "flying": 0x3678FF, "psychic": 0xD00053, "bug": 0x849400,
        "rock": 0x88762C, "ghost": 0x42428E, "dragon": 0x31229D,
        "dark": 0x442C21, "steel": 0x74747B, "fairy": 0xEC67EA,
    ]

    static func color(_ type: String) -> Color { Self.color(hex[type] ?? 0x777777) }
    static func dark(_ type: String) -> Color { Self.color(hexDark[type] ?? 0x555555) }

    /// The type's colour as *text* on the panel's dark background.
    ///
    /// The palette above is built for white text on a coloured chip, so its
    /// darker entries - Dark at 0x775544, Fighting, Ghost - turn muddy when
    /// they become the text themselves. Scaling every channel by the same
    /// factor raises the brightness while leaving hue and saturation alone, so
    /// each type stays recognisably itself rather than needing a second
    /// hand-picked palette to maintain.
    static func text(_ type: String) -> Color {
        let rgb = hex[type] ?? 0x777777
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        let peak = max(r, g, b)
        guard peak > 0, peak < 0.82 else { return Color(red: r, green: g, blue: b) }
        let k = 0.82 / peak
        return Color(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k))
    }

    private static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
}

/// Loads the type glyphs, stripping each icon's own background so the symbol
/// can be drawn over the palette above rather than its shipped colour.
enum TypeIcons {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func glyph(_ type: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[type] { return hit }
        guard let image = load(type) else { return nil }
        cache[type] = image
        return image
    }

    private static func load(_ type: String) -> NSImage? {
        guard let data = EmbeddedResources.data("types/\(type).png"),
              let source = NSImage(data: data),
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let keyed = keyOutBackground(cg)
        else { return nil }
        let image = NSImage(cgImage: keyed, size: NSSize(width: keyed.width, height: keyed.height))
        image.isTemplate = true
        return image
    }

    /// Turns "white symbol on a solid colour" into "white symbol on nothing".
    ///
    /// The background is whatever opaque colour dominates the icon, found with a
    /// coarse histogram; every pixel's new alpha is then how far it sits from
    /// that colour toward white. Keying on distance rather than brightness is
    /// what makes the pale types (steel, ice) come out right.
    private static func keyOutBackground(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Dominant opaque colour, quantized to 32-level bins.
        var bins: [Int: Int] = [:]
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 {
            let key = (Int(px[i]) / 32) << 10 | (Int(px[i + 1]) / 32) << 5 | (Int(px[i + 2]) / 32)
            bins[key, default: 0] += 1
        }
        guard let dominant = bins.max(by: { $0.value < $1.value })?.key else { return nil }
        let bg = (r: Double((dominant >> 10) & 31) * 32 + 16,
                  g: Double((dominant >> 5) & 31) * 32 + 16,
                  b: Double(dominant & 31) * 32 + 16)

        let span = max(1, sqrt(pow(255 - bg.r, 2) + pow(255 - bg.g, 2) + pow(255 - bg.b, 2)))
        for i in stride(from: 0, to: px.count, by: 4) {
            let originalAlpha = Double(px[i + 3]) / 255
            let d = sqrt(pow(Double(px[i]) - bg.r, 2)
                       + pow(Double(px[i + 1]) - bg.g, 2)
                       + pow(Double(px[i + 2]) - bg.b, 2))
            let alpha = min(1, d / span) * originalAlpha
            px[i] = 255; px[i + 1] = 255; px[i + 2] = 255
            px[i + 3] = UInt8(alpha * 255)
        }
        return ctx.makeImage()
    }
}
