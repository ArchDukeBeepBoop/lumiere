import SwiftUI

/// A secondary action sitting beside a primary one.
///
/// Borderless at rest, with a background only under the cursor. These used to be
/// outlined boxes: four equally-weighted rectangles in a row under a Play pill of
/// the same height, which left nothing on the header looking like the thing to
/// press. Everything but Play is a bare glyph now, and the tooltip carries the
/// name — the row went from competing with the primary action to sitting under it.
///
/// `isOn` is real state, not decoration: watched and favourite tint accent so the
/// row still answers "have I seen this?" at a glance without a label.
struct QuietIconButton: View {
    let systemName: String
    let help: String
    var isOn: Bool = false
    /// Destructive actions keep the danger colour even at rest. An unlabelled trash
    /// glyph that looks like every other icon in the row is a trap.
    var isDestructive: Bool = false
    /// Swaps the glyph for a spinner and refuses input. Used by anything that talks
    /// to the server and can take a moment — refreshing a collection's artwork.
    var isBusy: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 17))
                        .foregroundStyle(tint)
                }
            }
            // Grown with the Play pill above it. A 36 × 34 glyph under a 52pt
            // primary action reads as chrome rather than as a row of things to
            // click, and these are unlabelled — the target is most of what
            // advertises that they are controls at all.
            .frame(width: 42, height: 40)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(isHovering ? Theme.Palette.surfaceRaised : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .labelledHelp(help)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
    }

    private var tint: Color {
        if isDestructive { return Theme.Palette.danger }
        return isOn ? Theme.Palette.accent : Theme.Palette.textSecondary
    }
}
