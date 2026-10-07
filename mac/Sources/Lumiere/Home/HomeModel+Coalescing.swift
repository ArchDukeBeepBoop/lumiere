import Foundation
import LumiereKit

/// Dropping a home-screen load that has just been done.
///
/// Split from HomeModel.swift for the project's 300-line limit. See `load` for why
/// two lifecycle triggers exist and why neither can simply be deleted.
extension HomeModel {

    /// The two triggers that fire from the view's own lifecycle rather than from
    /// something changing. See `load`.
    static let lifecycleReasons: Set<String> = ["home appeared", "libraries changed"]

    /// How close together two identical lifecycle loads have to be to count as the
    /// same one. Generous enough to cover a slow first load, far short of anything a
    /// person could trigger twice on purpose.
    static let coalesceWindow: TimeInterval = 3

    /// Re-reads every shelf, and says so.
    ///
    /// Logged because this exact mechanism has been reported broken three times and
    /// each diagnosis was guesswork against a screen. A line per refresh, naming what
    /// asked for it, turns "the home screen did not update" into a question the log
    /// answers: either the refresh never fired, or it fired and the counts did not
    /// move. Those are different bugs and they were indistinguishable.
    ///
    /// For callers who know the *data* changed but hold none of the view's inputs —
    /// the sync, which finishes a library and wants the shelves to show it. Going
    /// through the view would mean a token, an `@Observable` read inside a body, and
    /// a `.task(id:)` re-firing; that path is how this was wired before and the
    /// shelves still did not move until you navigated away and back. A direct call
    /// has none of those links to be wrong.
    ///
    /// A no-op before the first load, which is correct: there is nothing on screen
    /// to refresh, and the first load is about to run with the real arguments.
    func refresh(_ reason: String = "unspecified") async {
        guard !lastLibraries.isEmpty else {
            Diagnostics.log("[home] refresh (\(reason)) skipped — nothing loaded yet")
            return
        }
        await load(libraries: lastLibraries, layout: lastLayout, reason: reason)
    }

    /// What the hero shows, in order.
    ///
    /// The spotlight when there is one, and the newest thing added when there is
    /// not — a library too thin or too unrated to fill a spotlight would otherwise
    /// open on a blank top third, which reads as a failure rather than as a small
    /// library. Never the resume list any more: Continue Watching is a row, and the
    /// hero is for things you have not started.
    var heroEntries: [LibraryEntry] {
        if !spotlight.isEmpty { return spotlight }
        // Nothing, rather than the newest thing added, until the spotlight has
        // actually been asked for.
        //
        // `loadSpotlight` runs near the end of a load, after the shelves — so with
        // an unconditional fallback the hero opened on whatever was imported most
        // recently and then swapped to the real backdrop a moment later. Every
        // launch began with the wrong picture. The fallback is still there for a
        // library too thin or too unrated to fill a spotlight; it just waits until
        // that is known rather than assuming it.
        return didLoadSpotlight ? Array(recentlyAdded.prefix(1)) : []
    }
}
