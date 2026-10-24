import SwiftUI

/// The sidebar's building blocks, on top of `PlayerGlass`: a group panel, a
/// slider row with its value and a reset, and a plain action row.

/// One group of rows on a slightly lighter plate, as tvOS groups a menu.
struct PlayerGroup<Content: View>: View {
    let title: String
    var footnote: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PlayerSectionLabel(title)
            VStack(alignment: .leading, spacing: 2) { content }
                .padding(Theme.Space.xs)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .fill(Theme.PlayerPalette.menuSelected))
            if let footnote {
                Text(footnote)
                    .font(Theme.Font.playerDetail)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.top, 2)
            }
        }
    }
}

/// A slider with a glyph, its name, the value in words, and a reset that
/// appears once it has moved. Changes apply as the thumb moves, so the
/// picture or the timing is judged while it changes.
struct PlayerSliderRow: View {
    let icon: String
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var neutral: Double = 0
    let format: (Double) -> String
    let onChange: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        let shown = draft ?? value
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon)
                    .font(Theme.Glyph.md(.medium))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.PlayerPalette.glyphPlate))
                Text(title).font(Theme.Font.playerRow.weight(.medium))
                Spacer(minLength: Theme.Space.sm)
                Text(format(shown))
                    .font(Theme.Font.playerRow.monospacedDigit())
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                if abs(shown - neutral) > step / 2 {
                    Button {
                        draft = nil
                        onChange(neutral)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(Theme.Glyph.sm(.bold))
                    }
                    .buttonStyle(.plain)
                    .labelledHelp("Reset \(title)")
                }
            }
            Slider(
                value: Binding(get: { draft ?? value }, set: { new in
                    let snapped = (new / step).rounded() * step
                    draft = snapped
                    onChange(snapped)
                }),
                in: range,
                onEditingChanged: { editing in if !editing { draft = nil } }
            )
            .tint(Theme.PlayerPalette.scrubPlayed)
            .controlSize(.small)
            .accessibilityLabel(title)
            .accessibilityValue(format(shown))
        }
        .foregroundStyle(Theme.Palette.onPlayerChrome)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 5)
    }
}

/// A row that does something, with a glyph and a line saying what.
struct PlayerActionRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var trailing: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: icon)
                    .font(Theme.Glyph.md(.medium))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.PlayerPalette.glyphPlate))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.Font.playerRow.weight(.medium))
                    if let detail {
                        Text(detail).font(Theme.Font.playerDetail)
                            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.sm)
                if let trailing {
                    Text(trailing).font(Theme.Font.playerRow.monospacedDigit())
                        .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                }
            }
            .foregroundStyle(Theme.Palette.onPlayerChrome)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(hovering ? Theme.PlayerPalette.menuHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

enum SidebarFormat {
    static func seconds(_ value: Double) -> String {
        abs(value) < 0.05 ? "In sync" : String(format: "%+.1f s", value)
    }
    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
    static func signed(_ value: Double) -> String {
        Int(value) == 0 ? "0" : String(format: "%+d", Int(value))
    }
}
