import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders Lumiere.icns from PrismArt — the same file the app draws with.
///
/// Compiled together with Sources/Lumiere/Design/PrismArt.swift (see
/// Scripts/bundle.sh). Every size is drawn, never downsampled, and macOS's
/// icon grid is kept: the tile is 824 of 1024 points, centred, with a shadow,
/// as every Apple icon since Big Sur.
@main
enum RenderIcon {
    static func main() {
        let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            let s = CGFloat(size)
            let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.setAllowsAntialiasing(true)
            c.interpolationQuality = .high
            let tile = s * 824 / 1024
            let inset = (s - tile) / 2
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.025,
                        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
            c.addPath(CGPath(roundedRect: CGRect(x: inset, y: inset, width: tile, height: tile),
                             cornerWidth: tile * 220 / 1024, cornerHeight: tile * 220 / 1024, transform: nil))
            c.setFillColor(PrismArt.groundMid)
            c.fillPath()
            c.restoreGState()
            PrismArt.draw(c, at: CGPoint(x: inset, y: inset), size: tile)
            let url = URL(fileURLWithPath: directory).appending(path: "icon_\(size).png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, c.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
        }
        print("rendered 7 sizes into \(directory)")
    }
}
