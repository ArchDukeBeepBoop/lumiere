import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Decoding artwork at the size it will actually be drawn.
///
/// This is the single most important thing in the app for memory. A 2000×3000
/// poster fully decoded is 2000 × 3000 × 4 bytes = **24 MB**. The same poster
/// decoded for a 150pt-wide cell on a 2× display is 300 × 450 × 4 = **540 KB**.
/// Forty-four times less, per poster, and a library grid shows dozens at once.
///
/// `CGImageSourceCreateThumbnailAtIndex` does this in one step: it never
/// materialises the full-size bitmap, unlike decode-then-resize.
public enum Downsample {

    /// Pure size math, separated out so it can be unit-tested without any pixels.
    ///
    /// Returns the longest-edge pixel size to request. Requesting by longest edge
    /// rather than width means one code path serves 2:3 posters and 16:9
    /// backdrops without either being under-sampled.
    public static func targetPixelSize(
        displayWidth: CGFloat,
        aspectRatio: CGFloat,
        screenScale: CGFloat,
        maximum: Int = 4096
    ) -> Int {
        guard displayWidth > 0, aspectRatio > 0, screenScale > 0 else { return 1 }

        let widthPixels = displayWidth * screenScale
        let heightPixels = widthPixels / aspectRatio
        let longest = max(widthPixels, heightPixels)

        // Round up to a whole pixel, then clamp. Rounding down produces a
        // half-pixel of softness on Retina that is genuinely visible on text
        // inside logo artwork.
        return min(maximum, max(1, Int(longest.rounded(.up))))
    }

    /// The width to ask Jellyfin for.
    ///
    /// Deliberately larger than the decode size: server-side resizing is cached
    /// per width, so requesting a handful of standard widths means a poster is
    /// generated once and reused, instead of the server re-encoding for every
    /// slightly different cell size. Overshooting costs a little bandwidth and
    /// saves a lot of server CPU.
    public static func requestWidth(forDisplayWidth displayWidth: CGFloat, screenScale: CGFloat) -> Int {
        let needed = displayWidth * screenScale
        let ladder = [160, 240, 320, 480, 640, 960, 1280, 1920, 2560, 3840]
        return ladder.first { CGFloat($0) >= needed } ?? ladder[ladder.count - 1]
    }

    /// Decodes image data straight to a thumbnail of at most `maxPixelSize` on
    /// its longest edge.
    public static func decode(data: Data, maxPixelSize: Int) -> CGImage? {
        // ImageIO does not read SVG, and Jellyfin's logos are often SVG — 37 of
        // them here. A nil here drew the logo's frame as an empty dark box over
        // the backdrop, where the title should have been. AppKit rasterises
        // SVG, so it is handed the vector and asked for a bitmap.
        if isSVG(data) { return rasteriseSVG(data, maxPixelSize: maxPixelSize) }

        let sourceOptions: [CFString: Any] = [
            // The full image is never decoded, only parsed for metadata.
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Decode once, here, rather than lazily on the render thread — which
            // would otherwise stutter the first frame of every scroll.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    /// SVG announces itself in its first bytes: `<svg` or an XML prologue.
    public static func isSVG(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return head.hasPrefix("<svg") || (head.hasPrefix("<?xml") && head.contains("<svg"))
    }

    /// Draws an SVG into a transparent bitmap of at most `maxPixelSize` on its
    /// longest edge.
    static func rasteriseSVG(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0
        else { return nil }
        let scale = min(1, CGFloat(maxPixelSize) / max(image.size.width, image.size.height))
        let width = max(1, Int(image.size.width * scale))
        let height = max(1, Int(image.size.height * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Bytes a decoded image occupies. Used as the `NSCache` cost so the limit is
    /// expressed in memory rather than in an arbitrary item count — the whole
    /// point, since a backdrop costs 20× what a poster does.
    public static func byteCost(of image: CGImage) -> Int {
        max(1, image.bytesPerRow * image.height)
    }
}
