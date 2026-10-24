import SwiftUI
import AppKit
import LumiereKit

/// How a `Theme.Palette` value becomes a colour.
///
/// Split from Theme.swift for the project's 300-line limit — the tokens grew when
/// the home screen went to Apple TV sizes. This half is the mechanism; the tokens
/// themselves stay in Theme.swift, which is the file anyone looking for a colour
/// opens.

// MARK: - Dynamic colour

extension Color {

    /// A colour that resolves against the current system appearance.
    ///
    /// Built on `NSColor`'s dynamic provider rather than SwiftUI's
    /// `@Environment(\.colorScheme)` so it works everywhere — including inside
    /// `NSViewRepresentable` chrome and layers, which never see the SwiftUI
    /// environment.
    static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightOpacity: Double = 1,
        darkOpacity: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            // The accent chosen in Settings › Look. See `AccentTheme`.
            let light = AccentTheme.map(light), dark = AccentTheme.map(dark)
            // The private room: the dark values, drained of colour. See RoomTheme.
            if RoomTheme.isOn {
                return NSColor(hex: RoomTheme.map(dark), alpha: darkOpacity)
            }
            // Paper is a light theme; its values stand in for the light ones.
            if PaperTheme.isOn {
                return NSColor(hex: PaperTheme.map(light), alpha: lightOpacity)
            }
            return NSColor(
                hex: isDark ? dark : light,
                alpha: isDark ? darkOpacity : lightOpacity
            )
        })
    }

    /// 0xRRGGBB literal initialiser, for the rare fixed colour that must not
    /// adapt — chrome drawn over video, for instance.
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha)
        )
    }
}

extension Color {
    /// The bright accent in either appearance — for the few places drawn over
    /// video or artwork, which are dark whatever the system says. Follows the
    /// choice in Settings › Look. See `AccentTheme`.
    static let fixedAccent = Color(nsColor: NSColor(name: nil) { _ in
        NSColor(hex: ArtworkAccent.hex ?? AccentTheme.map(0xC9A227), alpha: 1)
    })
}
