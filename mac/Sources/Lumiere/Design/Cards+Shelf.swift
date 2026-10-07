import SwiftUI

/// A shelf: a titled horizontal row that scrolls.
///
/// Split out of Cards.swift for the project's 300-line limit. Every home shelf
/// goes through this one type, which is the only reason their headers, their
/// horizontal insets and their hover room stay identical to each other.
struct Shelf<Content: View>: View {
    let title: String
    /// A short second line under the title — item counts, "12 shows". Optional
    /// because most shelves say everything they need to in the title.
    var subtitle: String?
    var action: (() -> Void)?
    /// See `ShelfTitleCard`.
    var actionTitle: String = "See All"
    var actionIcon: String = "chevron.right"
    /// How many tiles, and how wide each one is.
    ///
    /// Given rather than estimated, and that is the whole point. A `LazyHStack`
    /// inside a horizontal `ScrollView` reports a content width derived from the
    /// cells it has realised and a guess for the rest; when the guess runs long the
    /// row scrolls past its last tile into empty space, which is exactly what came
    /// back on the Anime shelf. The tiles here are uniform by construction — one
    /// card type per shelf, at one width — so the true width is arithmetic, and
    /// handing it over removes the estimate rather than arguing with it.
    ///
    /// Left nil by shelves whose tiles genuinely vary, which keeps SwiftUI's own
    /// behaviour for the case the arithmetic cannot describe.
    var itemCount: Int?
    var itemWidth: CGFloat?
    @ViewBuilder var content: Content

    /// The exact width of `itemCount` tiles with a gap between each pair.
    private var contentWidth: CGFloat? {
        guard let itemCount, let itemWidth, itemCount > 0 else { return nil }
        return CGFloat(itemCount) * itemWidth
            + CGFloat(max(0, itemCount - 1)) * Theme.Space.tileGap
    }

    var body: some View {
        // `sm`, not `md`: the row's own scroll view now carries `md` of vertical
        // padding to keep hover shadows off its edges, and that padding sits
        // between the title and the artwork too. Counted together the gap here is
        // still the 20pt it should be — a shelf title belongs to the row under it.
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ShelfTitleCard(title: title, subtitle: subtitle, action: action,
                actionTitle: actionTitle,
                actionIcon: actionIcon
            )

            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy, and the eager version it replaces was costing 457 MB.
                //
                // Measured, because this was reverted once on a reason that turned
                // out to be wrong. The claim then was that a `LazyHStack` cannot
                // size itself here because these shelves hand it "an opaque
                // @ViewBuilder rather than a ForEach it can count" — but every
                // caller passes a `ForEach` directly, so that was never true.
                //
                // What eager actually cost: an `HStack` builds every child and none
                // of them ever disappears, so `RemoteImage.onDisappear` — the thing
                // that releases the decoded bitmap — never fires for a tile scrolled
                // off the side. Ten shelves of twenty tiles is two hundred live
                // posters, each holding a decoded CGImage *and* a CALayer backing
                // store. On the owner's library that measured 227 MB of CG raster
                // and 229 MB of CoreAnimation against a 96 MB cache ceiling: the
                // cache was behaving, the views were not.
                LazyHStack(alignment: .top, spacing: Theme.Space.tileGap) {
                    content
                }
                // Each card a resting place: a flick settles with a whole card
                // at the margin, as tvOS rows do, never one cut in half.
                .scrollTargetLayout()
                .frame(width: contentWidth, alignment: .leading)
                // Hover scale *and its shadow* would otherwise be clipped by the
                // scroll view. `xs` was enough for the scale alone; the soft
                // shadow needs roughly its own radius of room or it is sliced off
                // square at the top and bottom of every hovered card.
                .padding(.vertical, Theme.Space.md)
            }
            // The inset as a margin, not padding, so the cards settle against it.
            .contentMargins(.horizontal, Theme.Space.shelfInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            // One focus section per row: ↑ and ↓ move between rows, ← and →
            // along one. See `KeyboardCard`.
            .focusSection()
        }
    }
}
