import AppKit

/// The iris, drawn small enough for the menu bar.
///
/// Not the app icon shrunk. A menu bar item wants a **template image**: pure
/// shape, no colour, which macOS then tints — black on a light bar, white on a
/// dark one, and inverted again while the menu is open. Handing it the amber
/// icon would produce a flat silhouette, because template rendering discards
/// everything but the alpha channel. So the glyph is redrawn here at 16pt with
/// its own proportions.
///
/// State is carried by the aperture: open while the server is serving, shut
/// while it is not. Shape rather than colour, because colour is the one thing a
/// template image cannot keep — and it is the same pair of states the two app
/// icons wear, so the bar and the Dock tell one story.
enum IrisGlyph {

    static func image(running: Bool) -> NSImage {
        // 18pt square is the usual menu bar allowance; the art sits inside it
        // with a little room so it does not crowd its neighbours.
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect, running: running)
            return true
        }
        // The whole point: let macOS own the colour.
        image.isTemplate = true
        return image
    }

    private static func draw(in rect: NSRect, running: Bool) {
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let housing: CGFloat = 7.0
        // Open while the server is serving, shut while it is not — the same
        // pair of states the two app icons wear, so the bar agrees with the
        // Dock without needing a second idea.
        let inradius: CGFloat = running ? 3.5 : 1.1
        let turn: CGFloat = running ? 0 : (.pi / 6) * 0.85
        let n = 6

        NSColor.black.setStroke()
        NSColor.black.setFill()

        func onEdge(_ i: Int, _ t: CGFloat) -> NSPoint {
            let a = turn + CGFloat(i) * 2 * .pi / CGFloat(n)
            return NSPoint(x: c.x + cos(a)*inradius - sin(a)*t,
                           y: c.y + sin(a)*inradius + cos(a)*t)
        }
        let half = inradius * tan(.pi / CGFloat(n))

        // A template image keeps only the silhouette, so the mechanism has to be
        // an outline rather than a fill: the annulus-and-hole drawing of the app
        // icon would arrive here as a solid disc with no iris in it at all.
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - housing, y: c.y - housing,
                                               width: housing*2, height: housing*2))
        ring.lineWidth = 1.5
        ring.stroke()

        let opening = NSBezierPath()
        for i in 0..<n {
            let p = onEdge(i, half)
            if i == 0 { opening.move(to: p) } else { opening.line(to: p) }
        }
        opening.close()
        opening.lineWidth = 1.3
        opening.stroke()

        let seams = NSBezierPath()
        seams.lineWidth = 1.3
        seams.lineCapStyle = .butt
        let reach = (housing*housing - inradius*inradius).squareRoot() - 0.6
        for i in 0..<n {
            seams.move(to: onEdge(i, half))
            seams.line(to: onEdge(i, reach))
        }
        seams.stroke()
    }
}
