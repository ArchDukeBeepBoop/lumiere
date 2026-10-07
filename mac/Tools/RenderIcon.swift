import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders Lumiere.icns from IrisArt — the same file the app draws with.
///
/// Compiled together with Sources/Lumiere/Design/IrisArt.swift (see
/// Scripts/bundle.sh), so the Dock icon and the icon Settings shows cannot
/// drift apart.
///
/// Every size is drawn, never downsampled: a 32px icon resampled from 1024
/// loses its seams to antialiasing and the iris collapses into a plain disc.
/// Drawn at 32, with the heavier seam weight IrisArt applies below 48, it
/// survives.
///
/// Wrapped in an entry point rather than left as top-level code, which Swift
/// allows only in a file named main.swift.
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

            IrisArt.drawBody(c, at: .zero, size: s)
            // Open: this is the player, and the player is where light is let
            // through. The server's controller draws the same iris shut.
            IrisArt.draw(c, at: .zero, size: s, openness: 1)

            let url = URL(fileURLWithPath: directory).appending(path: "icon_\(size).png")
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, c.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
        }
        print("rendered 7 sizes into \(directory)")
    }
}
