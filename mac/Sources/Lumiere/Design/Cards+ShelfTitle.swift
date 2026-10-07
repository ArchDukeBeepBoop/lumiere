import SwiftUI

/// A shelf's title, as a card rather than a label.
///
/// The previous header was a 19pt semibold string with a muted second line, and
/// against a row of 200pt posters it disappeared — it read as a caption that
/// happened to sit above some artwork rather than as the name of the row. Apple
/// TV's home screen makes the row heading the second-loudest thing on the page
/// after the artwork itself, and gets there with three moves this copies:
///
///   * weight, not colour — 26pt bold in `textPrimary`, no accent tint. Gold is
///     spent on progress and on the one primary action per screen, and a dozen
///     tinted headings would spend it a dozen times.
///   * a real block, not a line — the title and its subtitle are one unit with
///     the row's own left inset, so the eye reads title-then-tiles as one thing.
///   * "See All" as an affordance you can hit — a bordered pill, not four grey
///     words. It is the only control in a header, so it has to look like one.
///
/// Split from Cards+Shelf.swift so the shelf stays a layout and the header stays
/// a design; both are also under the 300-line limit with room to grow.
struct ShelfTitleCard: View {
    let title: String
    /// A short second line — a server name, an item count.
    var subtitle: String?
    /// "See All". Absent on shelves that have no fuller version of themselves,
    /// like Continue Watching.
    var action: (() -> Void)?
    /// What the pill says, and its glyph.
    ///
    /// "See All" for a shelf that has a fuller version of itself; "Refresh" for one
    /// that changes what it is showing rather than showing more of it. The two are
    /// different promises and the button should not make the wrong one.
    var actionTitle: String = "See All"
    var actionIcon: String = "chevron.right"

    @State private var isHoveringSeeAll = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title)
                    .font(Theme.Font.shelfTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    // Bold display type sets loose by default; pulling it in is
                    // most of what makes a heading look set rather than typed.
                    .tracking(-0.4)
                    .lineLimit(1)
                PaperRule()
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.lg)
            if let action {
                seeAll(action)
            }
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    private func seeAll(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Text(actionTitle)
                Image(systemName: actionIcon).font(Theme.Font.badge)
            }
            .font(Theme.Font.cardTitle)
            .foregroundStyle(
                isHoveringSeeAll ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
            )
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            // A fill only while hovered. Twelve permanently filled pills down a
            // home screen compete with the artwork they are meant to point at.
            .background(
                isHoveringSeeAll ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHoveringSeeAll = $0 }
        .animation(Theme.Motion.hover, value: isHoveringSeeAll)
    }
}
