import SwiftUI

/// The vocabulary every block below a detail header is built from.
///
/// Home was brought to this shape first: a `ShelfTitleCard` for a row's title, an
/// even `shelfGap` between rows, and rows that bleed to the window edge. The detail
/// pages built each of their sections inline at `sectionHeader` size — the type
/// used for a label *inside* a panel — so a film page read as a stack of form
/// headings rather than as the same shelves you had just scrolled past. These two
/// wrappers are the whole fix; the sections themselves only had to stop rolling
/// their own.
///
/// They now go through Home's own `ShelfTitleCard` rather than a lookalike. A
/// second implementation of a heading is a second thing to keep in step, and the
/// first pass at this proved the point: the detail shelves were at `shelfHeader`
/// (19pt semibold) while Home had already moved to `shelfTitle` (26pt bold), so
/// the two drifted apart within one commit of being aligned.

/// A titled block whose content sits inside the page margin: chapters, the
/// technical panel, a run of prose.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ShelfTitleCard(title: title)
            content.detailMargin()
        }
    }
}

/// A titled block that scrolls sideways: cast, extras, more-like-this, a
/// collection's shelves.
///
/// The scroll view itself is *not* inset — only the title and the cards inside it
/// are. A horizontal scroll view inset by the page margin clips the first and last
/// card's hover lift against its own edge, and stops the row running off the side
/// of the window the way Home's do, which is most of what makes a shelf read as a
/// shelf.
struct DetailShelf<Content: View>: View {
    let title: String
    /// A short second line. The cast row uses it to name the episode whose credits
    /// are being shown, which it has to, now that the row changes as you move along
    /// the strip.
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        // `sm`, not `md`, and `tileGap`, not `lg`: the numbers Home's `Shelf` uses,
        // for the same reasons it uses them. The row's own scroll view carries the
        // rest of the vertical gap as hover room.
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ShelfTitleCard(title: title, subtitle: subtitle)

            ScrollView(.horizontal, showsIndicators: false) {
                // An eager HStack, deliberately.
                //
                // This was made lazy to avoid building every cell of a long strip,
                // and it left blank space at the end of shelves: a LazyHStack
                // estimates its width from the cells it has realised, and these
                // shelves hand it an opaque @ViewBuilder rather than a ForEach it
                // can count, so the estimate is wrong and the scroll view extends
                // past the last tile into nothing. Every shelf here is bounded —
                // twenty items — so eager costs little and is correct.
                HStack(alignment: .top, spacing: Theme.Space.tileGap) {
                    content
                }
                .detailMargin()
                // Room for the hover lift *and its shadow*. `xs` was enough for the
                // scale alone; the soft shadow needs roughly its own radius or it is
                // sliced off square at the top and bottom of every hovered card.
                .padding(.vertical, Theme.Space.md)
            }
        }
    }
}

extension View {
    /// The page's horizontal margin.
    ///
    /// Applied per section rather than once around the whole column, so that a
    /// shelf can inset its cards while letting its scroll view run full width.
    ///
    /// `shelfInset`, not `xxl`. This was 32 while every home row started at 40, so
    /// navigating from a shelf into the page it belongs to shifted the whole
    /// column 8pt left — small enough to look like a rendering fault rather than a
    /// decision. One token means it cannot happen again.
    func detailMargin() -> some View {
        padding(.horizontal, Theme.Space.shelfInset)
    }
}

/// Sizes that belong to the detail pages rather than to the design system.
///
/// A detail header is not a home hero: it runs the window's full width at 16:9,
/// where Home works in a fixed 460pt band. Everything laid over it therefore has
/// perhaps twice the room, and the first pass at these pages sized the logo, the
/// Play pill and the episode stills from Home's tokens — which is most of why the
/// result read as cramped. These live here rather than in `Theme.Art` because no
/// other screen has any use for them.
enum DetailMetrics {
    /// The widest a paragraph of prose is allowed to run.
    ///
    /// A synopsis set to the full window is unreadable on a wide display — the eye
    /// loses the line it was on coming back from the right edge. Roughly 70
    /// characters at `Theme.Font.body`, which is the measure typography has settled
    /// on for continuous text.
    static let readingMeasure: CGFloat = 620

    /// The logo block over a detail backdrop, and the fallback title's measure.
    ///
    /// Apple TV gives the show's logo the bottom-left quarter of its backdrop and
    /// nothing else competes with it there. 440 × 150 is that share of a 16:9
    /// header at the window sizes this app is used at, and it is the single change
    /// that most makes the page look deliberate: at 290 × 110 a wide logo — which
    /// is most of them — was rendered at about a third of the height it was drawn
    /// for.
    static let logoWidth: CGFloat = 440
    static let logoHeight: CGFloat = 150

    /// The column holding Play and the quiet actions under it.
    ///
    /// Narrower than the logo on purpose. Play sits *beside* the synopsis rather
    /// than above it — stacking them pushed the episode strip off the bottom of
    /// the window, which is the mistake this layout was rebuilt out of — so this
    /// column only has to be wide enough for "Resume 1:23:45" with room to spare.
    static let actionColumnWidth: CGFloat = 320

    /// The Play pill's height. Apple TV's primary action is a genuinely large
    /// target; ours was the height of a menu button.
    static let playButtonHeight: CGFloat = 52

    /// An episode still. 360 × 202 at 16:9.
    ///
    /// The strip is eager and a merged anime series puts a few hundred cells in
    /// it, so this is a memory decision as much as a visual one. `RemoteImage`
    /// releases its bitmap on disappear, so the cost is set by how many tiles are
    /// *visible*, not by how many exist — and the arithmetic between 300 and 360
    /// is close to a wash: each still costs about 44% more to decode while roughly
    /// 17% fewer of them fit on screen, so the resident total rises by something
    /// like a fifth.
    ///
    /// Chosen against the page rather than in the abstract. The two neighbours
    /// that fix the scale are `Theme.Art.shelfPosterWidth` (200) below and
    /// `Theme.Art.continueCardWidth` (384) on Home: an episode still is the
    /// largest tile on this page and it should look it, but a strip built from
    /// full continue-cards fits barely three across a laptop window and reads as a
    /// second hero rather than as a season. 360 puts three and a half stills in a
    /// 1440pt window — the TV app's own count — which is also what makes the
    /// paging chevrons land on a sensible stride.
    static let episodeWidth: CGFloat = 360

    /// The block of type under an episode still: one line of `cardTitleLarge`, the
    /// `xxs` gap, and the reserved 17pt runtime line.
    ///
    /// Only the paging chevrons need this. They are centred on the *still* rather
    /// than on the cell, and an overlay has no way to ask how tall the labels
    /// under it turned out — so the number has to be stated once here instead of
    /// guessed at the call site.
    static let episodeLabelHeight: CGFloat = 36

    /// A paging chevron on the episode strip. Large enough to be a comfortable
    /// target over artwork without covering the still it sits on.
    static let stripChevron: CGFloat = 40

    /// A cast portrait. 88 was chosen against 120pt posters, then 120 against
    /// 200pt ones; the stills beside it are 360 now and the row went back to
    /// reading as a footnote for the third time.
    static let castPortrait: CGFloat = 140
    /// The cell around a portrait — wide enough for a character name and an
    /// actor's underneath it without either truncating at the first comma.
    static let castCellWidth: CGFloat = 180

    /// The headshot at the top of a person page.
    ///
    /// Larger than a cast portrait because it is the subject rather than a cell in
    /// a row — the same step up a detail header's poster takes over a grid tile.
    /// Sized against the `Theme.Font.hero` name beside it: much bigger and the
    /// name reads as a caption on a photograph rather than as the page's title.
    static let personPortrait: CGFloat = 168

    /// The label column in the About block, and the measure the block runs to.
    ///
    /// A details list set to the full width of a wide window is unreadable for the
    /// same reason a paragraph is: "Audio" on the left edge and "English (Dolby
    /// Digital 5.1)" a thousand points away are not obviously the same row.
    static let aboutLabelWidth: CGFloat = 140
    static let aboutMeasure: CGFloat = 720
}
