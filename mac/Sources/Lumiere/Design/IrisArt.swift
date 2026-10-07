import CoreGraphics
import Foundation

/// The iris, drawn once.
///
/// Compiled into the app *and* into `Tools/RenderIcon.swift`, so the icon in the
/// Dock and the icon drawn in Settings are the same geometry rather than two
/// drawings that agree until one is edited. Nothing here imports SwiftUI or
/// AppKit for that reason — the command-line renderer has no app to import.
///
/// An iris is an annulus of overlapping leaves whose straight leading edges
/// bound a regular polygon. Closing it shrinks that polygon *and turns it*:
/// leaves that shrink without turning read as a hole getting smaller, while
/// leaves that turn read as a mechanism. That rotation is the whole difference
/// between this and a circle.
public enum IrisArt {

    public static let amberLight = CGColor(red: 1.00, green: 0.92, blue: 0.70, alpha: 1)
    public static let amberDeep  = CGColor(red: 0.90, green: 0.68, blue: 0.26, alpha: 1)
    public static let bodyTop    = CGColor(red: 0.095, green: 0.105, blue: 0.125, alpha: 1)
    public static let bodyBottom = CGColor(red: 0.035, green: 0.04, blue: 0.055, alpha: 1)
    /// The blades: a shade above the body, so the mechanism sits *on* the icon
    /// rather than looking like a hole cut through it.
    public static let blade      = CGColor(red: 0.155, green: 0.165, blue: 0.195, alpha: 1)

    /// The rounded-square body every icon in this family shares.
    public static func drawBody(_ c: CGContext, at o: CGPoint, size s: CGFloat) {
        let inset = s * 0.085
        let rect = CGRect(x: o.x + inset, y: o.y + inset, width: s - inset*2, height: s - inset*2)
        c.saveGState()
        c.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width*0.2237,
                         cornerHeight: rect.height*0.2237, transform: nil))
        c.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [bodyTop, bodyBottom] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: o.y + s),
                             end: CGPoint(x: 0, y: o.y), options: [])
        c.restoreGState()
    }

    /// The mechanism. `openness` is 1 wide open, 0 shut.
    ///
    /// Dark blades and a lit opening, which is the weight the rest of this
    /// family uses — amber marks on a dark ground, not the reverse — and also
    /// the truer picture: an iris is a hole that lets light through, not a gold
    /// disc.
    public static func draw(_ c: CGContext, at o: CGPoint, size s: CGFloat, openness: CGFloat) {
        let n = 6
        let mid = CGPoint(x: o.x + s/2, y: o.y + s/2)
        let housing = s * 0.300
        let inradius = s * (0.042 + 0.150 * openness)
        // About 25° across the full travel. Less and the two states look like
        // one picture at two scales.
        let turn = (1 - openness) * (.pi / CGFloat(n)) * 0.85

        func angle(_ i: Int) -> CGFloat { turn + CGFloat(i) * 2 * .pi / CGFloat(n) }
        func onEdge(_ i: Int, _ t: CGFloat) -> CGPoint {
            let a = angle(i)
            return CGPoint(x: mid.x + cos(a)*inradius - sin(a)*t,
                           y: mid.y + sin(a)*inradius + cos(a)*t)
        }
        let half = inradius * tan(.pi / CGFloat(n))

        func openingPath(_ c: CGContext) {
            c.move(to: onEdge(0, -half))
            for i in 0..<n { c.addLine(to: onEdge(i, half)) }
            c.closePath()
        }

        // The housing rim. Without it the shut state has no visible circle —
        // dark blades on a dark body show nothing but their seams, and six
        // amber seams radiating from a point read as a starburst rather than as
        // a closed aperture. The menu bar glyph works precisely because it
        // draws this ring; the app icon needs it for the same reason.
        //
        // Dimmer when open, where the lit opening already describes the circle.
        c.saveGState()
        c.beginPath()
        c.addArc(center: mid, radius: housing, startAngle: 0, endAngle: .pi*2, clockwise: false)
        c.setLineWidth(s * 0.020)
        c.replacePathWithStrokedPath()
        c.clip()
        c.setAlpha(0.45 + 0.35 * (1 - openness))
        fillAmber(c, at: o, size: s, top: 0.82, bottom: 0.18)
        c.restoreGState()

        // Blades.
        c.saveGState()
        c.beginPath()
        c.addArc(center: mid, radius: housing, startAngle: 0, endAngle: .pi*2, clockwise: false)
        openingPath(c)
        c.setFillColor(blade)
        c.fillPath(using: .evenOdd)
        c.restoreGState()

        // The light behind the opening. Stronger when open, because a wider
        // aperture is literally more light — the one place in this drawing
        // where the physics and the graphic design want the same thing.
        let bloom = s * (0.18 + 0.20 * openness)
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 0.82, blue: 0.45, alpha: 0.34 + 0.24*openness),
                     CGColor(red: 1, green: 0.76, blue: 0.34, alpha: 0)] as CFArray,
            locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: mid, startRadius: 0,
                             endCenter: mid, endRadius: bloom, options: [])

        c.saveGState()
        c.beginPath(); openingPath(c); c.clip()
        fillAmber(c, at: o, size: s, top: 0.72, bottom: 0.28)
        c.restoreGState()

        // The seams: each leading edge continued from the polygon vertex out to
        // the housing. This is the line you actually see between two leaves.
        //
        // Thicker below 48px. At icon sizes a hairline seam antialiases into
        // nothing and the mechanism collapses into a plain disc — the same
        // reason the menu bar glyph is drawn rather than downsampled.
        let reach = (housing*housing - inradius*inradius).squareRoot()
        // Thinner when shut: with no opening to balance them, six full-weight
        // seams become the whole picture.
        var weight: CGFloat = s < 48 ? 0.034 : 0.022
        if openness < 0.2 { weight *= 0.78 }
        c.setLineWidth(s * weight)
        c.setLineCap(.butt)
        for i in 0..<n {
            c.beginPath()
            c.move(to: onEdge(i, half))
            c.addLine(to: onEdge(i, reach))
            c.replacePathWithStrokedPath()
            c.saveGState(); c.clip()
            fillAmber(c, at: o, size: s, top: 0.80, bottom: 0.20)
            c.restoreGState()
        }
    }

    /// The family's vertical amber gradient, clipped to the current path.
    static func fillAmber(_ c: CGContext, at o: CGPoint, size s: CGFloat,
                          top: CGFloat, bottom: CGFloat) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [amberLight, amberDeep] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: o.y + s*top),
                             end: CGPoint(x: 0, y: o.y + s*bottom), options: [])
    }
}

extension IrisArt {

    /// The original mark: a lamp at the left and its beam widening to the right.
    ///
    /// Kept so the icon that has been in someone's Dock for months is still
    /// available. Redrawn here rather than shipped as a second PNG, for the
    /// same reason as everything else in this file — one geometry, no assets to
    /// fall out of step.
    public static func drawBeam(_ c: CGContext, at o: CGPoint, size s: CGFloat) {
        let lamp = CGPoint(x: o.x + s*0.355, y: o.y + s*0.5)

        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 0.80, blue: 0.42, alpha: 0.30),
                     CGColor(red: 1, green: 0.76, blue: 0.34, alpha: 0)] as CFArray,
            locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: lamp, startRadius: 0,
                             endCenter: lamp, endRadius: s*0.30, options: [])

        c.saveGState()
        c.beginPath()
        c.move(to: lamp)
        c.addLine(to: CGPoint(x: o.x + s*0.80, y: o.y + s*0.755))
        c.addLine(to: CGPoint(x: o.x + s*0.80, y: o.y + s*0.245))
        c.closePath()
        c.clip()
        let beam = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 0.85, blue: 0.50, alpha: 0.95),
                     CGColor(red: 0.85, green: 0.62, blue: 0.20, alpha: 0.10)] as CFArray,
            locations: [0, 1])!
        c.drawLinearGradient(beam, start: lamp,
                             end: CGPoint(x: o.x + s*0.80, y: o.y + s*0.5), options: [])
        c.restoreGState()

        c.setFillColor(amberLight)
        c.fillEllipse(in: CGRect(x: lamp.x - s*0.072, y: lamp.y - s*0.072,
                                 width: s*0.144, height: s*0.144))
    }
}
