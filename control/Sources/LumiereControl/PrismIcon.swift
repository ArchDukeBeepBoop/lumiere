import AppKit

/// The app icon drawn at a size, for the menu's header and the Settings window.
///
/// The header's prism is lit while the server serves and grey when it stops —
/// the same two states the menu bar glyph wears, so a glance anywhere tells
/// the same story.
enum PrismIcon {
    @MainActor
    static func image(lit: Bool, size: CGFloat) -> NSImage {
        let pixels = Int(size * 2)
        guard let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: NSSize(width: size, height: size)) }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high
        PrismArt.draw(c, size: CGFloat(pixels), lit: lit)
        guard let cg = c.makeImage() else { return NSImage(size: NSSize(width: size, height: size)) }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}
