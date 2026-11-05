import CoreGraphics
import Foundation

/// The prism: Lumiere's icon, drawn in code.
///
/// A faceted hexagon — three planes sharing one bright source — around a
/// play button, on a midnight tile, edged in a teal-to-violet light. Drawn
/// rather than loaded so every size is rendered at that size (a 32px icon
/// resampled from 1024 loses its seams) and so the app and its build script
/// share one geometry: Tools/RenderIcon.swift compiles this file to make the
/// app icon. This is an identical copy of Lumiere's own PrismArt.swift.
///
/// Coordinates are the design's own 1024-point grid, top-left origin, as in
/// Icons/08-prism.svg; `draw` flips and scales them onto the context.
enum PrismArt {

    // The palette, from the design.
    static let groundTop = rgb(0x252449), groundMid = rgb(0x171B37), groundBottom = rgb(0x10182D)
    static let edge = [rgb(0xD8F5E9), rgb(0x8FE5E3), rgb(0x9296FF), rgb(0xD7AEFF)]
    static let buttonLight = rgb(0xFFF8E2), buttonMint = rgb(0xD9F5EE), playMark = rgb(0x292847)

    /// The whole icon into a square of `size` at `origin`. `lit` false draws
    /// the edges in grey — the server's controller while it is stopped.
    static func draw(_ c: CGContext, at origin: CGPoint = .zero, size: CGFloat, lit: Bool = true, tile: Bool = true) {
        c.saveGState()
        c.translateBy(x: origin.x, y: origin.y + size)
        c.scaleBy(x: size / 1024, y: -size / 1024)
        let space = CGColorSpaceCreateDeviceRGB()

        if tile {
            let tilePath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                                  cornerWidth: 220, cornerHeight: 220, transform: nil)
            c.addPath(tilePath)
            c.clip()
            linear(c, space, [groundTop, groundMid, groundBottom], [0, 0.52, 1],
                   from: CGPoint(x: 116, y: 76), to: CGPoint(x: 916, y: 952))
            // The ambient light behind the prism.
            if let ambient = CGGradient(colorsSpace: space, colors: [
                rgb(0x4A8EAB, 0.28 * (lit ? 1 : 0.4)), rgb(0x6557A7, 0.13), rgb(0x171B37, 0),
            ] as CFArray, locations: [0, 0.63, 1]) {
                c.drawRadialGradient(ambient, startCenter: CGPoint(x: 512, y: 468), startRadius: 0,
                                     endCenter: CGPoint(x: 512, y: 468), endRadius: 440, options: [])
            }
        }

        let colours = lit ? edge : [rgb(0xC9CCD6), rgb(0xA4A8B6), rgb(0x8A8EA0), rgb(0xA3A6B4)]
        let hexagon = path([(512, 222), (766, 368), (766, 656), (512, 804), (258, 656), (258, 368)])

        // A soft halo ring, then the facets with their shadow.
        c.saveGState()
        c.setShadow(offset: .zero, blur: 44, color: rgb(0x9296FF, lit ? 0.45 : 0.15))
        c.setStrokeColor(rgb(0x8FE5E3, lit ? 0.10 : 0.04))
        c.setLineWidth(32)
        c.strokeEllipse(in: CGRect(x: 216, y: 216, width: 592, height: 592))
        c.restoreGState()

        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -18 * (tile ? 1 : 0)), blur: 38, color: rgb(0x070B19, 0.45))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        fill(c, space, path([(512, 222), (766, 368), (512, 512), (258, 368)]),
             [rgb(0xDDF8E9, 0.14), rgb(0x91B5FF, 0.04)], from: CGPoint(x: 288, y: 250), to: CGPoint(x: 739, y: 513))
        fill(c, space, path([(258, 368), (512, 512), (512, 804), (258, 656)]),
             [rgb(0x9AE8E5, 0.10), rgb(0x847EFF, 0.13)], from: CGPoint(x: 273, y: 371), to: CGPoint(x: 512, y: 790))
        fill(c, space, path([(766, 368), (512, 512), (512, 804), (766, 656)]),
             [rgb(0x8DA6FF, 0.08), rgb(0xD9A8FF, 0.14)], from: CGPoint(x: 512, y: 512), to: CGPoint(x: 766, y: 785))

        // The outline, and the three seams meeting at the centre. Heavier
        // below 64 pixels, where a hairline would vanish.
        let small = size < 64
        strokeGradient(c, space, hexagon, width: small ? 48 : 30, colours: colours)
        let seams = CGMutablePath()
        seams.move(to: CGPoint(x: 512, y: 222)); seams.addLine(to: CGPoint(x: 512, y: 512))
        seams.move(to: CGPoint(x: 258, y: 368)); seams.addLine(to: CGPoint(x: 512, y: 512))
        seams.addLine(to: CGPoint(x: 766, y: 368))
        seams.move(to: CGPoint(x: 512, y: 512)); seams.addLine(to: CGPoint(x: 512, y: 804))
        c.setAlpha(0.78)
        strokeGradient(c, space, seams, width: small ? 30 : 18, colours: colours)
        c.setAlpha(1)

        // The play button at the heart of it.
        c.setFillColor(rgb(0x7986D6, 0.30))
        c.fillEllipse(in: CGRect(x: 421, y: 421, width: 182, height: 182))
        c.saveGState()
        c.addEllipse(in: CGRect(x: 432, y: 432, width: 160, height: 160))
        c.clip()
        linear(c, space, [buttonLight, buttonMint], [0, 1], from: CGPoint(x: 440, y: 428), to: CGPoint(x: 584, y: 593))
        c.restoreGState()
        let play = CGMutablePath()
        play.move(to: CGPoint(x: 496, y: 471))
        play.addCurve(to: CGPoint(x: 475, y: 483), control1: CGPoint(x: 487, y: 465), control2: CGPoint(x: 475, y: 472))
        play.addLine(to: CGPoint(x: 475, y: 541))
        play.addCurve(to: CGPoint(x: 496, y: 553), control1: CGPoint(x: 475, y: 552), control2: CGPoint(x: 487, y: 559))
        play.addLine(to: CGPoint(x: 544, y: 524))
        play.addCurve(to: CGPoint(x: 544, y: 500), control1: CGPoint(x: 553, y: 519), control2: CGPoint(x: 553, y: 506))
        play.closeSubpath()
        c.addPath(play)
        c.setFillColor(playMark)
        c.fillPath()
        c.endTransparencyLayer()
        c.restoreGState()

        if tile && size >= 64 {
            // The inner rim catching the light.
            c.addPath(path([(512, 250), (744, 383), (744, 649), (512, 783), (280, 649), (280, 383)]))
            c.setStrokeColor(rgb(0xF1F7FF, 0.12))
            c.setLineWidth(3)
            c.setLineJoin(.round)
            c.strokePath()
        }
        c.restoreGState()
    }

    // MARK: - Helpers

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func path(_ points: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    private static func linear(_ c: CGContext, _ space: CGColorSpace, _ colours: [CGColor], _ stops: [CGFloat],
                               from: CGPoint, to: CGPoint) {
        guard let g = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: stops) else { return }
        c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func fill(_ c: CGContext, _ space: CGColorSpace, _ shape: CGPath, _ colours: [CGColor],
                             from: CGPoint, to: CGPoint) {
        c.saveGState()
        c.addPath(shape)
        c.clip()
        linear(c, space, colours, [0, 1], from: from, to: to)
        c.restoreGState()
    }

    /// A stroke filled with the edge light, teal at the top left to violet
    /// at the bottom right.
    private static func strokeGradient(_ c: CGContext, _ space: CGColorSpace, _ shape: CGPath,
                                       width: CGFloat, colours: [CGColor]) {
        c.saveGState()
        c.addPath(shape)
        c.setLineWidth(width)
        c.setLineJoin(.round)
        c.setLineCap(.round)
        c.replacePathWithStrokedPath()
        c.clip()
        linear(c, space, colours, [0, 0.34, 0.69, 1], from: CGPoint(x: 282, y: 268), to: CGPoint(x: 738, y: 761))
        c.restoreGState()
    }
}
