import SwiftUI

/// Tokens for the player's glass panels — see `PlayerGlass.swift`. Their own
/// file because Theme+Player.swift is at its line budget.
public extension Theme.PlayerPalette {
    /// The capsule behind a segmented picker, and the white thumb that slides
    /// along it, as on Apple TV's info panel.
    static let segmentTrack = Color.white.opacity(0.10)
    static let segmentThumb = Color.white.opacity(0.92)
    static let segmentOnThumb = Color.black.opacity(0.85)
    /// The disc behind a row's glyph.
    static let glyphPlate = Color.white.opacity(0.12)
    /// A light wash over the blur, so the glass reads as smoked rather than as
    /// the black slab it used to be.
    static let glassTint = Color.black.opacity(0.44)
    /// The panels' fill over video, standing in for blur plus tint.
    static let glassSheen = Color.white.opacity(0.10)
    static let glassSolid = Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.82)
    /// The rim: light caught on the top edge, fading down the sides.
    static let glassRimTop = Color.white.opacity(0.32)
    static let glassRimBottom = Color.white.opacity(0.05)
    /// A row under the pointer, and a ticked row.
    static let menuHover = Color.white.opacity(0.13)
    static let menuSelected = Color.white.opacity(0.07)
}

public extension Theme.Radius {
    /// A glass panel over video. Rounder than the 14 it was, as visionOS and
    /// tvOS 17 round theirs.
    static let playerGlass: CGFloat = 22
}

public extension Theme.Font {
    static let playerSection = SwiftUI.Font.system(size: 11, weight: .semibold)
    static let playerDetail = SwiftUI.Font.system(size: 11, weight: .regular)
}

public extension Theme.Motion {
    /// A segmented thumb sliding to its new place.
    static let segment = Animation.spring(response: 0.3, dampingFraction: 0.82)
}

public extension Theme.PlayerMetric {
    /// The Audio and Subtitles menu: wide enough for its two columns where the
    /// window allows, one column in a small window.
    static func trackPanelWidth(in size: CGSize) -> CGFloat {
        guard size.width > 0 else { return panelWidth }
        return min(max(panelWidth, size.width * 0.30), 480)
    }
}
