import AppKit

/// The app icon drawn at a size and an opening, for the menu's header and the
/// Settings window.
///
/// The header's iris opens while the server serves and closes when it stops —
/// the same two states the Dock icon and the menu bar glyph wear, so a glance
/// anywhere tells the same story.
enum IrisIcon {
    @MainActor
    static func image(openness: CGFloat, size: CGFloat) -> NSImage {
        let pixels = Int(size * 2)
        guard let c = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: NSSize(width: size, height: size)) }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high
        IrisArt.drawBody(c, at: .zero, size: CGFloat(pixels))
        IrisArt.draw(c, at: .zero, size: CGFloat(pixels), openness: openness)
        guard let cg = c.makeImage() else { return NSImage(size: NSSize(width: size, height: size)) }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}
