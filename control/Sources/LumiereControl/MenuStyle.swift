import SwiftUI

/// The menu's design primitives, taken from macOS's own menu bar extras.
///
/// Not an interpretation of Apple's style — its specific furniture. Rows carry
/// their icon inside a small grey circle that fills with the accent colour when
/// the thing is on, as Wi-Fi and Bluetooth do since Sonoma. The two primary
/// switches are Control Center tiles. Section headers are sentence-case and
/// secondary, as in every system menu, not the spaced capitals of a magazine.
/// The highlight is a soft grey rounded rectangle, because inside a menu bar
/// window that is what the system draws — the blue bar belongs to NSMenu.
///
/// And the colour is the user's, not ours: `Color.accentColor` follows System
/// Settings › Appearance, so someone with a graphite Mac gets a graphite menu.
enum Menu {
    static let accent = Color.accentColor

    static let title = Font.system(size: 13, weight: .bold)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11)
    static let section = Font.system(size: 12, weight: .semibold)

    static let width: CGFloat = 300
    /// The inset Control Center uses between the window edge and its modules.
    static let gutter: CGFloat = 12
    static let rowHeight: CGFloat = 32
    static let iconCircle: CGFloat = 24
    static let cardRadius: CGFloat = 12
}

/// A section heading: sentence case, secondary, as in the Wi-Fi menu.
struct MenuSection: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Menu.section)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Menu.gutter + 2)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// The grey circle with a glyph in it, accent-filled when `active`.
struct IconCircle: View {
    let symbol: String
    var active = false
    var size: CGFloat = Menu.iconCircle

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(active ? Menu.accent : Color.primary.opacity(0.1)))
    }
}

/// A row: circled icon, title, optional subtitle, optional trailing detail.
struct MenuRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var active = false
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconCircle(symbol: symbol, active: active)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Menu.body)
                    if let subtitle {
                        Text(subtitle).font(Menu.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(Menu.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.opacity)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .padding(.horizontal, 6)
            .frame(minHeight: Menu.rowHeight + (subtitle == nil ? 0 : 6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Hover(isOn: isHovering && isEnabled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .padding(.horizontal, Menu.gutter - 6)
    }
}

/// A plain text command with its shortcut at the trailing edge — the
/// "Wi-Fi Settings…" line at the foot of every system menu.
struct MenuCommand: View {
    let title: String
    /// A ⌘-key that works while the menu is open, shown at the trailing edge
    /// in the tertiary colour system menus use for their key equivalents.
    var key: Character? = nil
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Menu.body)
                Spacer()
                if let key {
                    Text("⌘\(String(key).uppercased())").font(Menu.body).foregroundStyle(.tertiary)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Hover(isOn: isHovering && isEnabled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .modifier(CommandKey(key: key))
        .padding(.horizontal, Menu.gutter - 8)
    }
}

private struct CommandKey: ViewModifier {
    let key: Character?
    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            content
        }
    }
}

/// Text that reads as information rather than an action.
struct MenuNote: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(Menu.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Menu.gutter + 2)
            .padding(.vertical, 2)
    }
}

/// The soft grey hover a menu bar window draws.
struct Hover: View {
    let isOn: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(isOn ? 0.09 : 0))
    }
}

/// The hairline rule between groups in a system menu, inset as theirs are.
struct MenuRule: View {
    var body: some View {
        Divider().padding(.horizontal, Menu.gutter + 2).padding(.vertical, 5)
    }
}

/// A Control Center module: a lighter rounded card on the menu's material.
struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Menu.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Menu.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

extension View {
    func card() -> some View { modifier(Card()) }
}
