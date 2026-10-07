import SwiftUI

/// The design primitives the menu is built from.
///
/// Two traditions, and they agree more than they differ. From Apple: system
/// materials, SF Symbols, a hover highlight that is a rounded shape rather than
/// a full-bleed bar, and controls where the platform puts them. From
/// Squarespace: hierarchy carried by *space* rather than by lines and boxes, a
/// type scale of three sizes and no more, and a single accent used sparingly
/// enough that it still means something when it appears.
///
/// The practical consequence is a lot of restraint. There is one colour in this
/// menu that is not greyscale, and it appears on exactly one element.
enum Menu {
    /// Lumiere's amber, taken from the app icon so the family reads as one
    /// thing. Used only for the running state — an accent that appears
    /// everywhere is decoration, not signal.
    static var accent: Color { MenuLook.current.accent }

    /// A three-step type scale. Title, body, caption — anything a menu needs to
    /// say fits in one of them, and a fourth size would only blur the hierarchy
    /// the other three establish.
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    /// Section labels: small, spaced, uppercase. The one typographic flourish,
    /// and it earns its place by removing the need for dividers between groups.
    static let label = Font.system(size: 10, weight: .semibold)

    /// A spacing scale in multiples of four, because a rhythm you can name is
    /// one you can keep. Sizes picked once here rather than sprinkled as
    /// literals through the layout.
    static let gutter: CGFloat = 14
    static let rowHeight: CGFloat = 30
    static let iconColumn: CGFloat = 22
    static let width: CGFloat = 288
}

/// A section heading.
struct MenuSection: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Menu.label)
            .kerning(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Menu.gutter)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

/// One tappable row: symbol, label, optional trailing detail.
///
/// The icon sits in a fixed-width column so every label starts on the same
/// vertical line — the thing that makes a list of unrelated actions read as one
/// list rather than as several. It is also why the symbols are all the same
/// optical weight.
struct MenuRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: Menu.iconColumn, alignment: .leading)
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                Text(title)
                    .font(Menu.body)
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(Menu.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Menu.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MenuRowHighlight(isOn: isHovering && isEnabled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .padding(.horizontal, Menu.gutter - 10)
    }
}

/// A row that reads as text rather than as an action — progress, a result, a
/// reason. Same grid as MenuRow so it does not break the column.
struct MenuNote: View {
    let symbol: String?
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11))
                } else {
                    Color.clear
                }
            }
            .frame(width: Menu.iconColumn, alignment: .leading)
            Text(text)
                .font(Menu.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Menu.gutter)
        .padding(.vertical, 3)
    }
}
