import SwiftUI

/// Whether the enclosing block is drawn over a photograph rather than over the page.
///
/// The home screen's hero was fixed by hand — every `Text` in it switched from
/// `textPrimary`/`textSecondary` to the `onArtwork` pair with a shadow. The detail
/// pages could not be fixed the same way, because their synopsis and rating chips
/// are `ExpandableText` and `RatingChips`, shared with the About block further down
/// the page where the page colours are correct. One component cannot hardcode both.
///
/// So the *context* carries it. A header that overlays a backdrop marks its content
/// `.onArtwork()`, and anything inside that reads `Theme.Palette.text(...)` gets
/// white-on-picture instead of near-black-on-white. Outside such a header the flag
/// is false and nothing changes.
///
/// Why this matters at all: `textPrimary` in light mode is `#1D1D1F`. A near-black
/// title over a bright film still is not dim, it is gone — and `textMuted` at
/// `#6B7381` is gone in both appearances.
private struct OnArtworkKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isOnArtwork: Bool {
        get { self[OnArtworkKey.self] }
        set { self[OnArtworkKey.self] = newValue }
    }
}

extension View {

    /// Marks everything inside as drawn over artwork.
    ///
    /// Also applies the shadow, once, at the top of the block rather than per
    /// `Text`: a drop shadow on a container costs one offscreen pass for the whole
    /// header instead of one per label, and it means a line added to the header
    /// later cannot forget to be legible.
    func onArtwork(_ isOn: Bool = true) -> some View {
        environment(\.isOnArtwork, isOn)
            .shadow(color: isOn ? .black.opacity(0.5) : .clear, radius: 5, y: 1)
    }
}

extension Theme.Palette {

    /// Titles and anything else set at `textPrimary` weight.
    static func primaryText(onArtwork: Bool) -> Color {
        onArtwork ? onArtworkText : textPrimary
    }

    /// Synopsis, metadata lines, credits — anything at `textSecondary`.
    static func secondaryText(onArtwork: Bool) -> Color {
        onArtwork ? onArtworkTextMuted : textSecondary
    }

    /// Labels and captions. Deliberately the *same* white-at-78% as the secondary
    /// pair rather than a third, dimmer one: over a photograph the distinction
    /// between a 65% white and a 78% white is not legibility, it is decoration, and
    /// the muted grey it replaces is the least legible colour in the palette.
    static func mutedText(onArtwork: Bool) -> Color {
        onArtwork ? onArtworkTextMuted : textMuted
    }
}
