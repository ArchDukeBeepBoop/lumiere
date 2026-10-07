import CoreGraphics

/// How large the player's settings panel should be, given the player it is drawn
/// over.
///
/// A pure function in the kit rather than a constant in the theme, because the
/// clamping is the part that has to be right and the only way to check it is to
/// ask it about window sizes that do not exist on this machine.
public enum PlayerPanelSize {

    /// What it was before this became a function, and what it falls back to
    /// before the first layout reports a size.
    public static let fallback = CGSize(width: 640, height: 420)

    /// The settings panel.
    ///
    /// It used to be a hard 640 × 420, which is two wrong sizes rather than one.
    /// At the 720pt minimum window that covered nearly the whole picture — and
    /// every control in the panel is judged *against* the picture, which is the
    /// reason it is a panel over the film and not a sheet. On a large display in
    /// fullscreen the same 640 sat in the middle like a dialog from another app.
    ///
    /// A share of the player, clamped at both ends: it grows with the room it
    /// has, never outgrows a small window, and stops before it becomes a wall on
    /// a 5K display.
    public static func settingsPanel(in player: CGSize) -> CGSize {
        guard player.width > 0, player.height > 0 else { return fallback }
        let width = min(max(520, player.width * 0.44), 820, player.width * 0.9)
        // 3:2 is the shape the two columns want — a category rail beside a list
        // of controls — so height follows width rather than being clamped
        // separately, which would letterbox the panel on a wide display.
        let height = min(max(360, width / 1.5), player.height * 0.8)
        return CGSize(width: width, height: height)
    }
}
