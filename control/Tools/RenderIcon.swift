import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders LumiereControl.icns from IrisArt — the same geometry Lumiere uses.
///
/// Compiled alongside Sources/LumiereControl/IrisArt.swift, so the two apps'
/// icons are one drawing in two states rather than two drawings that resemble
/// each other.
///
/// Every size is drawn, never downsampled: a 32px icon resampled from 1024
/// loses its seams to antialiasing and the iris collapses into a plain disc.
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
            // Shut. This is the server's controller, and the server is where the
            // library is kept rather than where it is let out — the same
            // mechanism Lumiere wears open.
            IrisArt.draw(c, at: .zero, size: s, openness: 0)

            let url = URL(fileURLWithPath: directory).appending(path: "icon_\(size).png")
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, c.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
        }
        print("rendered 7 sizes into \(directory)")
    }
}
