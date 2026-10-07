import Foundation

/// How much of each thing a home shelf shows.
///
/// Split from HomeModel.swift for the project's 300-line limit, and they belong
/// together anyway: each is a judgement about how many tiles earn their memory
/// against how much gets hidden, and reading them side by side is what makes the
/// one that is deliberately different — Continue Watching — obvious.
extension HomeModel {

    /// How many tiles a home shelf holds.
    ///
    /// Was twenty. A shelf builds its strip eagerly — the lazy version left blank
    /// space past the last tile — so every tile on a realised shelf decodes its
    /// poster whether or not it is scrolled into view, and the tiles just doubled
    /// in area. Twelve at 200pt costs about what twenty at 140pt did, and showing
    /// fewer, larger things is the change that was asked for rather than a
    /// concession to it.
    static let shelfLength = 12

    /// How far Continue Watching reaches.
    ///
    /// Not `shelfLength`. Every other shelf is a *selection* — the twelve newest, the
    /// twelve highest rated — where a cap is the whole design. This one is a list of
    /// unfinished business, and a cap on it silently hides things you started: on
    /// this library there are 31 of them and the shelf was showing twelve, so
    /// nineteen titles you had not finished were simply not there.
    ///
    /// Bounded rather than unbounded because the row is built eagerly enough to
    /// matter and nobody has 200 unfinished films they intend to return to. If the
    /// cap is ever reached the oldest are the ones lost, which is the right end.
    static let resumeLength = 100

    /// How far Next Up reaches.
    ///
    /// The same number as `resumeLength` and for the same reason: this is the other
    /// list on the home screen that is not a selection. Continue Watching is what
    /// you started and did not finish; Next Up is the episode after the last one you
    /// finished — both are answers to "what was I in the middle of", and a cap on
    /// either silently drops shows you are partway through. It was `shelfLength`, so
    /// a twelfth series in progress had no next episode anywhere on the screen.
    ///
    /// Costs more than the resume cap does, because this one is a request to the
    /// server rather than a local read — one request either way, but a longer answer
    /// to parse and cache. Bounded for the same reason: nobody is partway through a
    /// hundred shows, and if they are, the oldest are the ones lost.
    static let nextUpLength = 100

    /// When a row starts offering a See All.
    ///
    /// Not about hidden items — both rows reach 100, so on any ordinary account they
    /// are already showing everything. It is about *shape*: past about six cards the
    /// row is a horizontal scroll, and a horizontal scroll is the worst way to answer
    /// "what have I left unfinished" because you cannot see the list, only a window
    /// onto it. The See All opens the same titles as a grid, all visible at once and
    /// grouped by the library each came from.
    ///
    /// Six because four fit a wide window without scrolling and six is the first
    /// count where something is reliably off the right-hand edge.
    static let seeAllThreshold = 6
}
