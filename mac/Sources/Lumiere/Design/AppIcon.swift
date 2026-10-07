import AppKit
import SwiftUI

/// Which icon the app wears.
///
/// Two designs, and they are not decoration: the aperture is the current family
/// — the same mechanism the server's controller wears shut — and the beam is
/// the original lamp-and-projector mark, kept because someone who has had it in
/// their Dock for months should not have it taken away by an update.
///
/// The images are *drawn*, never loaded. `IrisArt` is the same code that
/// renders Lumiere.icns at build time, so what Settings previews and what the
/// Dock shows are one geometry.
public enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case aperture
    case beam

    public var id: String { rawValue }

    /// The preference key. Read at launch as well as in Settings, because the
    /// Dock forgets a runtime icon when the app quits.
    public static let storageKey = "appIcon"

    public var title: String {
        switch self {
        case .aperture: return "Aperture"
        case .beam: return "Beam"
        }
    }

    public var explanation: String {
        switch self {
        case .aperture:
            return "An iris open to let the light through. Matches the server's "
                 + "controller, which wears the same iris shut."
        case .beam:
            return "The original mark: a lamp and its projector beam."
        }
    }

    /// The icon at a given size, drawn fresh.
    ///
    /// Not cached. An icon is drawn a handful of times in a session — twice for
    /// the Settings previews, once when applied — and a cache keyed on size and
    /// choice would be more code than the drawing it saves.
    @MainActor
    public func image(size: CGFloat) -> NSImage {
        let pixels = Int(size * 2)   // Retina; the previews are small
        guard let c = CGContext(data: nil, width: pixels, height: pixels,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: NSSize(width: size, height: size)) }
        c.setAllowsAntialiasing(true)
        c.interpolationQuality = .high

        let s = CGFloat(pixels)
        IrisArt.drawBody(c, at: .zero, size: s)
        switch self {
        case .aperture: IrisArt.draw(c, at: .zero, size: s, openness: 1)
        case .beam: IrisArt.drawBeam(c, at: .zero, size: s)
        }

        guard let image = c.makeImage() else {
            return NSImage(size: NSSize(width: size, height: size))
        }
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }

    /// Applies to the running app.
    ///
    /// `NSApp.applicationIconImage` overrides the bundle's icns for as long as
    /// the app runs, and the Dock forgets it on quit — which is why the choice
    /// is re-applied at launch rather than written into the bundle. Writing to
    /// the bundle would also break the code signature.
    @MainActor
    public func apply() {
        // The default costs nothing to restore properly: handing back nil lets
        // AppKit use the bundle's own icns, which is already this drawing.
        NSApp.applicationIconImage = self == .aperture ? nil : image(size: 512)
    }
}
