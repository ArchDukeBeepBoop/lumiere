import AppKit

/// The prism, drawn small enough for the menu bar.
///
/// Not the app icon shrunk. A menu bar item wants a **template image**: pure
/// shape, no colour, which macOS then tints — black on a light bar, white on a
/// dark one, and inverted again while the menu is open. Template rendering
/// keeps only the alpha channel, so the glyph is redrawn here at 18pt as an
/// outline with its own proportions.
///
/// State is carried by shape, because colour is the one thing a template
/// image cannot keep: while the server serves, the prism holds the icon's play
/// mark; while it is stopped, the prism is empty — only its three seams.
enum PrismGlyph {

    static func image(running: Bool) -> NSImage {
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
        let r: CGFloat = 7.6
        // A pointy-topped hexagon, as in the icon.
        let corners = (0..<6).map { i -> NSPoint in
            let a = CGFloat.pi / 2 + CGFloat(i) * .pi / 3
            return NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        }
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outline = NSBezierPath()
        outline.move(to: corners[0])
        corners.dropFirst().forEach { outline.line(to: $0) }
        outline.close()
        outline.lineWidth = 1.5
        outline.lineJoinStyle = .round
        outline.stroke()

        if running {
            // The play mark, centred on its own visual weight.
            let play = NSBezierPath()
            play.move(to: NSPoint(x: c.x - 2.2, y: c.y + 3.4))
            play.line(to: NSPoint(x: c.x + 3.6, y: c.y))
            play.line(to: NSPoint(x: c.x - 2.2, y: c.y - 3.4))
            play.close()
            play.lineJoinStyle = .round
            play.fill()
        } else {
            // Top, lower-left and lower-right corners meet at the centre.
            let seams = NSBezierPath()
            seams.lineWidth = 1.2
            for i in [0, 2, 4] {
                seams.move(to: c)
                seams.line(to: corners[i])
            }
            seams.stroke()
        }
    }
}
