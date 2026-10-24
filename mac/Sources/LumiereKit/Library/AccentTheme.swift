import Foundation

/// The accent colour, chosen in Settings › Look — VLC's redesign asked for
/// this in so many words: keep the identity, let people pick the colour.
///
/// Gold is Lumiere's own and the default. Like `PaperTheme`, it is a map from
/// the standard values to the chosen ones, applied where every colour is
/// resolved, so no view knows the accent can change.
public enum AccentTheme: String, CaseIterable, Identifiable, Sendable {
    case gold, blue, purple, pink, red, orange, green, graphite

    public static let storageKey = "accentChoice"

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    /// The current choice, read at resolve time.
    public static var current: AccentTheme {
        AccentTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .gold
    }

    /// Strong (on white), bright (on dark), muted light, muted dark.
    var values: (strong: UInt32, bright: UInt32, mutedLight: UInt32, mutedDark: UInt32) {
        switch self {
        case .gold: return (0x8A6E12, 0xC9A227, 0xE2D3A0, 0x5C4F28)
        case .blue: return (0x0A64C8, 0x3D9BFF, 0xBFD9F5, 0x1E3A5C)
        case .purple: return (0x7A3FB8, 0xB57CF0, 0xDCCAF2, 0x3E2A5A)
        case .pink: return (0xB8195A, 0xFF6FA5, 0xF6C6D8, 0x5C2539)
        case .red: return (0xB8322A, 0xFF6B5E, 0xF4C5BF, 0x5A2622)
        case .orange: return (0xA85400, 0xFF9F2E, 0xF5D6B0, 0x5C3A14)
        case .green: return (0x1E7A3C, 0x4CD27A, 0xC2E8CC, 0x1F4A2C)
        case .graphite: return (0x55555C, 0xAEAEB2, 0xD9D9DE, 0x3A3A3C)
        }
    }

    /// The swatch Settings draws.
    public var swatch: UInt32 { values.bright }

    /// A gold value → the chosen accent's. Anything else passes through.
    public static func map(_ hex: UInt32) -> UInt32 {
        let choice = current
        guard choice != .gold else { return hex }
        let gold = AccentTheme.gold.values, mine = choice.values
        switch hex {
        case gold.strong: return mine.strong
        case gold.bright, 0xB58F26: return mine.bright
        case gold.mutedLight: return mine.mutedLight
        case gold.mutedDark: return mine.mutedDark
        default: return hex
        }
    }
}
