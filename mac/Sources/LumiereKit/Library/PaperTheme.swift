import Foundation

/// Paper: warm stock, ink-dark type, a red-brown accent. Always light.
///
/// Implemented where every palette colour is resolved (`Color.dynamic`), as a
/// map from the standard light value to its paper one, rather than as a
/// second set of tokens: views keep asking for `Theme.Palette.surface` and
/// never learn a theme exists, and a token added later without a paper value
/// simply falls through to the standard light one instead of breaking.
public enum PaperTheme {

    public static let storageKey = "appTheme"
    public static let paper = "paper"

    /// Read from preferences at resolve time — `UserDefaults` is an in-memory
    /// read, and a colour provider cannot see the SwiftUI environment.
    public static var isOn: Bool {
        UserDefaults.standard.string(forKey: storageKey) == paper
    }

    /// Standard light value → paper value.
    public static let ink: [UInt32: UInt32] = [
        0xFFFFFF: 0xF6F1E6, // canvas: the page
        0xF2F2F4: 0xEDE6D6, // chrome
        0xF5F5F7: 0xF0EADC, // surface
        0xE9E9EE: 0xE6DDCA, // surfaceRaised
        0xD9D9DE: 0xDACFB8, // border
        0xB6B6BE: 0xBFB29A, // borderStrong
        0x1D1D1F: 0x2A241E, // textPrimary, play button: ink
        0x5C5C63: 0x5B5146, // textSecondary
        0x86868C: 0x877B6B, // textMuted
        0xB0B0B8: 0xB5A993, // textDisabled
        0x8A6E12: 0x8E3B2C, // accent: oxblood ink
        0xE2D3A0: 0xE6CBBF, // accentMuted
        0xC7C7CE: 0xC9BDA6, // badgeNeutralBorder
    ]

    /// Light values that stay exactly as they are on paper, each on purpose:
    /// the unwatched orange, the badge and genre tints, danger and success —
    /// colours that mean something and read on warm stock as well as white.
    /// A light value in Theme.swift must be in `ink` or here; a test holds that.
    public static let keptAsIs: Set<UInt32> = [
        0xF07B22, 0xBE2F2C, 0x1C8560, 0x000000,
        0x715A0F, 0xD8C68C, 0x1B6349, 0x9CD2BD, 0x1A5486, 0xA3C6E6,
        0x8A3B63, 0x8A3B2E, 0x6B3B8A, 0x3F4A8A, 0x2E7A5C, 0x2E5E8A, 0x1F5F63,
    ]

    public static func map(_ light: UInt32) -> UInt32 { ink[light] ?? light }
}
