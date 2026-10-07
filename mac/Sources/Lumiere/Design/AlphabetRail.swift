import SwiftUI
import LumiereKit

/// A–Z down the right edge of a list, for jumping rather than scrolling.
///
/// One rail, used by every shelf. It began inside the music browser at nine points
/// with thirteen-point rows, which was small enough to be fiddly and easy to miss —
/// so this is bigger, hit-tested to a wider strip than it draws, and highlights the
/// letter under the pointer.
///
/// Letters with nothing behind them are drawn dimmed rather than hidden: a rail
/// that changes shape as a filter narrows a list is one you cannot build muscle
/// memory for, and the gaps themselves say something about the library.
struct AlphabetRail: View {
    /// letter → the id to scroll to. Built once by the caller, since the answer
    /// only changes when the list does.
    let destinations: [String: String]
    let proxy: ScrollViewProxy
    /// Where the target should land. Lists want `.top`; a grid reads better with a
    /// little air above the row.
    var anchor: UnitPoint = .top
    /// Called before scrolling, for lists that page: a letter three thousand rows
    /// down does not exist in the view hierarchy yet, and `scrollTo` on an id that
    /// has never been rendered does nothing at all. Loading first is what makes the
    /// jump land rather than silently fail.
    var prepare: ((String) async -> Void)?

    @State private var hovered: String?
    @State private var isPreparing: String?

    var body: some View {
        VStack(spacing: 1) {
            ForEach(AlphabetIndex.letters, id: \.self) { letter in
                let target = destinations[letter]
                Text(letter)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colour(for: letter, enabled: target != nil))
                    .frame(width: 22, height: 18)
                    .background(
                        hovered == letter && target != nil
                            ? Theme.Palette.surfaceRaised : .clear,
                        in: .rect(cornerRadius: 4)
                    )
                    // The whole cell is the target, not just the glyph. A single
                    // character is a very small thing to hit on the way past.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard let target else { return }
                        guard let prepare else {
                            withAnimation(Theme.Motion.transition) {
                                proxy.scrollTo(target, anchor: anchor)
                            }
                            return
                        }
                        isPreparing = letter
                        Task {
                            await prepare(letter)
                            // A frame for the newly loaded rows to exist before
                            // being scrolled to. Without it the scroll runs against
                            // the hierarchy as it was a moment ago.
                            try? await Task.sleep(for: .milliseconds(50))
                            withAnimation(Theme.Motion.transition) {
                                proxy.scrollTo(target, anchor: anchor)
                            }
                            isPreparing = nil
                        }
                    }
                    .onHover { hovered = $0 ? letter : nil }
            }
        }
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, 2)
        .background(Theme.Palette.chrome.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        .padding(.trailing, Theme.Space.sm)
        // Never the thing a keyboard tabs into: it is a shortcut past a list, and
        // twenty-seven stops between one control and the next is not a shortcut.
        .focusable(false)
    }

    private func colour(for letter: String, enabled: Bool) -> Color {
        guard enabled else { return Theme.Palette.textDisabled }
        if isPreparing == letter { return Theme.Palette.textPrimary }
        return hovered == letter ? Theme.Palette.textPrimary : Theme.Palette.accent
    }
}

/// A filter field sized for a shelf's toolbar.
///
/// Narrows what is already on screen rather than querying the server — that is
/// Search, which is a section of its own and takes you away from where you are.
/// The count is shown while filtering so an empty result reads as a filter result
/// rather than as a list that failed to load.
struct ShelfSearchField: View {
    @Binding var text: String
    var placeholder: String = "Filter"
    /// How many rows survive, or nil to show no count.
    var matchCount: Int?
    /// How many exist in total, when only part of them is loaded. Shown with no
    /// filter typed, because "120 of 412" is the fact a paged list has to state —
    /// otherwise a partly-loaded grid looks like the whole set.
    var totalCount: Int?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textMuted)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textPrimary)
                .focused($isFocused)
                .frame(width: 130)

            if text.isEmpty, let totalCount, let matchCount {
                Text("\(matchCount) of \(totalCount)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }

            if !text.isEmpty {
                if let matchCount {
                    Text("\(matchCount)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 4)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .strokeBorder(
                    isFocused ? Theme.Palette.accent : Theme.Palette.border, lineWidth: 1
                )
        }
    }
}
