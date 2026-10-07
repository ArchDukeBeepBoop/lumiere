import SwiftUI
import LumiereKit

/// The ring that says where the keyboard is.
///
/// A ring rather than the hover lift the mouse gets: the two mean different
/// things and should not be confused, and a scale on a keyboard-focused tile
/// would reflow nothing but still read as the tile having been picked up.
struct KeyboardFocusRing: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    RoundedRectangle(
                        cornerRadius: Theme.Radius.posterLarge, style: .continuous
                    )
                    .strokeBorder(Theme.Palette.accent, lineWidth: 3)
                    .padding(-3)
                }
            }
    }
}

extension View {
    func keyboardFocusRing(_ isFocused: Bool) -> some View {
        modifier(KeyboardFocusRing(isFocused: isFocused))
    }
}


/// A tooltip *and* a name a screen reader can say.
///
/// Every icon-only control in the app carried `.labelledHelp(…)` and nothing else. A
/// help string is a tooltip: it appears on hover, for people using a mouse and
/// looking at the screen. VoiceOver reads none of it, so the toolbars were a row
/// of unnamed buttons and the folder browser's layout picker — a `Picker("")`
/// with `.labelsHidden()` — announced as an unnamed segmented control.
///
/// One modifier rather than two calls at each of twenty-seven sites, so the two
/// cannot drift apart.
struct LabelledHelp: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .help(text)
            .accessibilityLabel(Text(text))
    }
}

extension View {
    func labelledHelp(_ text: String) -> some View {
        modifier(LabelledHelp(text: text))
    }
}
