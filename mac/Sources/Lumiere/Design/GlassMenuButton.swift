import SwiftUI

/// A choice as Apple TV's title pages draw it: a glass capsule naming the
/// current value, a small up-down chevron, and the system menu behind it.
///
/// Replaces the bordered pop-up button macOS draws for `Picker(.menu)`, which
/// sat on hero artwork like a form field from a preferences window.
struct GlassMenuButton<Option: Hashable, ID: Hashable>: View {
    let icon: String?
    let options: [Option]
    let id: KeyPath<Option, ID>
    @Binding var selection: ID
    let label: (Option) -> String
    var help: String = ""

    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(options, id: id) { option in
                Button {
                    selection = option[keyPath: id]
                } label: {
                    if option[keyPath: id] == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if let icon { Image(systemName: icon).font(Theme.Glyph.md(.semibold)) }
                Text(current).font(Theme.Font.cardTitle).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.xs(.bold))
                    .opacity(0.7)
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 7)
            .background { GlassFill(shape: Capsule()) }
            .overlay { Capsule().strokeBorder(Theme.Palette.border.opacity(isHovering ? 1 : 0.6), lineWidth: 1) }
            .scaleEffect(isHovering ? 1.03 : 1)
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .labelledHelp(help)
    }

    private var current: String {
        options.first { $0[keyPath: id] == selection }.map(label) ?? "Choose"
    }
}
