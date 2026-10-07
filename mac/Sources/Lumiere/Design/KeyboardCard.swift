import SwiftUI
import LumiereKit

/// A card the keyboard can reach: the TV app's focus grammar on a Mac.
///
/// Home was mouse-only. Each card now takes focus — a thin accent ring says
/// which, drawn only while it has it — the arrow keys move along a row and
/// between rows (each row is a focus section), Return opens the card and Space
/// plays it. Nothing is drawn until a key is pressed, so the pointer user sees
/// the same screen as before.
struct KeyboardCard: ViewModifier {
    let id: String
    let cornerRadius: CGFloat
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Palette.accent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onKeyPress(.return) {
                NotificationCenter.default.post(name: .openDetail, object: id)
                return .handled
            }
            .onKeyPress(.space) {
                NotificationCenter.default.post(name: .openDetail, object: "play:" + id)
                return .handled
            }
    }
}

extension View {
    func keyboardCard(id: String, cornerRadius: CGFloat = 8) -> some View {
        modifier(KeyboardCard(id: id, cornerRadius: cornerRadius))
    }
}
