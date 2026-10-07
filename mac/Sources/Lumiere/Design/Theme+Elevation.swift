import SwiftUI

/// The hover gesture and the motion around it.
///
/// Split from Theme.swift for the project's 300-line rule — the file crossed it as
/// the Apple TV sizing tokens landed.
public extension Theme {

    /// The hover gesture, in one place.
    ///
    /// Every card in the app lifts the same way — a small scale plus a soft
    /// shadow, no ring and no bounce. Kept as tokens rather than repeated per
    /// card because the thing that makes it read as one system is that a poster
    /// on Home and a poster in the library move by exactly the same amount.
    enum Elevation {
        public static let hoverScale: CGFloat = 1.06
        public static let hoverShadow: CGFloat = 22
        public static let hoverShadowY: CGFloat = 12
    }

    // MARK: - Artwork geometry

    /// Poster and backdrop aspect ratios, kept here so the image pipeline and the
    /// views agree on the exact pixel size to decode at.
    enum Art {
        public static let posterAspect: CGFloat = 2.0 / 3.0
        public static let backdropAspect: CGFloat = 16.0 / 9.0
        public static let thumbAspect: CGFloat = 16.0 / 9.0

        /// Default on-screen poster width in points. The image pipeline multiplies
        /// this by the screen scale to pick a decode size.
        /// The default tile in a library grid.
        ///
        /// 140 for a long time, and at that size a wall of posters is dense
        /// enough that no single one is legible as artwork — you scan the grid
        /// for a shape you already know rather than looking at anything. One
        /// step larger is the difference between finding and browsing, and the
        /// size slider still reaches the old width for anyone who wants density.
        public static let posterWidth: CGFloat = 170
        public static let episodeThumbWidth: CGFloat = 240
        /// The wide continue-watching card. 16:9 at Infuse's size.
        public static let continueCardWidth: CGFloat = 448

        /// A poster on a home shelf. 200 × 300 at 2:3, which is Apple TV's own
        /// portrait card.
        ///
        /// Deliberately *not* `posterWidth`: that token is the default tile in a
        /// library grid, where the job is to show a whole library and 140pt is
        /// right. A home shelf has the opposite job — a handful of things,
        /// presented — so it is a separate size rather than a change to the grid
        /// everyone has already tuned with the tile-size slider.
        ///
        /// Bigger tiles cost memory: a 200pt poster decodes to roughly twice the
        /// bitmap of a 140pt one, and a shelf builds its whole strip eagerly. That
        /// is paid for by `HomeModel.shelfLength`, which shows fewer of them.
        public static let shelfPosterWidth: CGFloat = 200

        /// A genre card. 16:9 and narrower than a continue card, so a genre row
        /// reads as navigation rather than as a second continue-watching shelf.
        public static let genreCardWidth: CGFloat = 300

        /// A library card. Portrait, because a library is a wall of posters and
        /// the card that opens one should look like what is behind it — at genre
        /// size and 16:9 the two navigation rows would be indistinguishable
        /// sitting a few points apart. Deliberately *not* `shelfPosterWidth`: a
        /// row holds one card per library and has to be scannable rather than
        /// scrolled, and eleven at 200pt is three window-widths.
        public static let libraryCardWidth: CGFloat = 180

        /// The home hero. Taller than 16:9 at any usable window width, so the
        /// backdrop is cropped rather than letterboxed and the title block has
        /// somewhere to sit that is not on top of the subject's face.
        public static let heroHeight: CGFloat = 460
        /// As tall as a hero may get once it follows the backdrop's own 16:9.
        ///
        /// 620 held it well below a series detail page's header, which takes its
        /// full 16:9 with no ceiling at all — so the same artwork was visibly
        /// smaller on the home screen than one click away, which is backwards for
        /// the largest thing on the page. 820 is 16:9 of a 1,460-point content
        /// column: a maximised window on a 16-inch display. At that size and below
        /// the hero is uncropped; only a wider display starts trimming it. The cap
        /// stays because without one the shelves go off screen on a large monitor.
        public static let heroHeightMax: CGFloat = 820
        public static let heroLogoWidth: CGFloat = 380
        public static let heroLogoHeight: CGFloat = 110
        /// The hero's resume track. Short on purpose: a full-width progress bar
        /// under a title reads as a loading indicator.
        public static let heroProgressWidth: CGFloat = 220

        /// The circular back/forward control on the hero's rotation. Sized against
        /// the quick-link pills rather than against the artwork: by the time it is
        /// drawn the scrim has faded the backdrop into the page, so it is chrome on
        /// the page rather than a badge on a photograph.
        public static let heroPageControl: CGFloat = 28
        /// One position marker in the hero's rotation.
        public static let heroPageDot: CGFloat = 6
    }
}
