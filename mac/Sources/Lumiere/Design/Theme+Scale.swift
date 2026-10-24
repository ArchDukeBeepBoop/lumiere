import SwiftUI

/// The tokens the views were reaching past Theme for: symbol and small-label
/// sizes, the larger corner radii, and the slow, ambient animations.
///
/// The Phase C audit found 102 `.font(.system(size:))` calls across thirty
/// distinct sizes, twenty-three numeric corner radii and twelve literal
/// durations. Each one was reasonable where it stood; together they were
/// thirty slightly different sizes for what is visually five. This puts them
/// on one scale, the way SF Symbols' own small/medium/large does.
public extension Theme {

    /// Symbol and compact-label sizes. Weight and design stay the caller's.
    enum Glyph {
        /// 9 — a badge's glyph, a disclosure caret.
        public static func xs(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 9, weight: weight, design: design) }
        /// 11 — a glyph beside caption text, a close button's ×.
        public static func sm(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 11, weight: weight, design: design) }
        /// 13 — a glyph beside body text, a row's icon.
        public static func md(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 13, weight: weight, design: design) }
        /// 16 — a toolbar or transport glyph.
        public static func lg(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 16, weight: weight, design: design) }
        /// 22 — a primary transport glyph.
        public static func xl(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 22, weight: weight, design: design) }
        /// 34 — an empty state's or a sheet's lead symbol.
        public static func hero(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 34, weight: weight, design: design) }
        /// 44 — a full-screen state's symbol.
        public static func display(_ weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default) -> SwiftUI.Font { .system(size: 44, weight: weight, design: design) }
    }
}

public extension Theme.Radius {
    /// An app icon tile or a grouped panel in a sheet.
    static let tile: CGFloat = 14
    /// A floating glass card over the page.
    static let glassCard: CGFloat = 18
    /// The navigation pill.
    static let sidebarPill: CGFloat = 26
}

public extension Theme.Motion {
    /// A fade that should be noticed but not watched: a pause card, a glance.
    static let fade = Animation.easeInOut(duration: 0.4)
    /// Ambient colour following the content: the home backdrop, a glow.
    static let ambient = Animation.easeInOut(duration: 0.7)
    /// The screensaver's crossfade and the launch pulse.
    static let slowFade = Animation.easeInOut(duration: 1.4)
    /// The screensaver's Ken Burns drift.
    static let drift = Animation.linear(duration: 11)
    /// A message leaving.
    static let dismiss = Animation.easeIn(duration: 0.3)
}

public extension Theme.Palette {
    /// The ground under video and the screensaver: always black. One of the
    /// fixed tokens, with `playerChrome`, because film is.
    static let videoGround = Color.black
    /// Text and glyphs on the unwatched marker's fixed orange.
    static let onUnwatched = Color.white
}
