import SwiftUI

/// ⌘-click to start a multi-select, on the cards that offer one.
///
/// Its own modifier so the gesture is absent — not merely inert — on the cards
/// that do not. A recognizer attached to every tile competes with the scroll
/// view for the same events, which is felt rather than seen.
struct SelectionPress: ViewModifier {
    let begin: (() -> Void)?

    func body(content: Content) -> some View {
        if let begin {
            // ⌘-click, as Finder does — not a press-and-hold. Holding for
            // under half a second started selecting, and a click whose button
            // stayed down a moment (easy on a trackpad) selected a show instead
            // of opening it, then every click after toggled more. With the
            // modifier required, a plain click always reaches the link.
            content.highPriorityGesture(TapGesture().modifiers(.command).onEnded { begin() })
        } else {
            content
        }
    }
}
