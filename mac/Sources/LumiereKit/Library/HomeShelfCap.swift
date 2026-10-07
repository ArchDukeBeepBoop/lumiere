import Foundation

/// How many shelves the home screen is allowed to draw.
///
/// The review's diagnosis was that the screen is long because it is redundant,
/// and its instruction was to cap it at seven and put the rest behind Library.
/// The overhaul that followed added two shelves and removed none, so the screen
/// came out of it *longer* than it went in — about seventeen rows on this
/// library.
///
/// Pure, because the interesting part is not the number seven but which rows the
/// cap keeps: an empty shelf must not spend one of the seven places, or a screen
/// with three empty rows shows four.
public enum HomeShelfCap {

    /// Seven, from the review. Not a magic number so much as the point at which
    /// a home screen stops being a front page and becomes a list.
    public static let limit = 7

    /// - Parameters:
    ///   - sections: the running order, as the user arranged it.
    ///   - isEmpty: whether a section would draw nothing. Empty sections are
    ///     skipped rather than counted, and never appear in either list.
    ///   - showAll: the escape hatch. Someone who wants every row should be able
    ///     to have it — the cap is an opinion about a default, not a rule about
    ///     what people are allowed to see.
    /// - Returns: the rows to draw, and the ones held back.
    public static func apply<Section>(
        to sections: [Section],
        isEmpty: (Section) -> Bool,
        showAll: Bool = false
    ) -> (visible: [Section], heldBack: [Section]) {
        let drawable = sections.filter { !isEmpty($0) }
        guard !showAll, drawable.count > limit else { return (drawable, []) }
        return (Array(drawable.prefix(limit)), Array(drawable.dropFirst(limit)))
    }
}
