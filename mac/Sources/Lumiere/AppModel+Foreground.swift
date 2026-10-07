import Foundation
import LumiereKit

/// Letting the screen in front of the user go first.
///
/// `LibraryRepository` is an actor, so every caller queues on it, and SQLite's write
/// transactions block readers on top of that. At launch the startup sync and the
/// home screen's first load ask for it at the same moment — and the sync, which
/// nobody is looking at, wins by starting a fraction earlier and then holding the
/// actor for the length of a page fetch and its write.
///
/// Measured on this library: the home screen's queries cost 0.26s run against the
/// database with nothing else touching it, and 6–8s inside the app. That is roughly
/// thirty times over, spent on the slowest and most visible moment there is.
///
/// The fix is ordering, not concurrency. Nothing here makes a query faster; it
/// stops the one nobody is waiting for from going first.
@MainActor
extension AppModel {

    /// How long the sync will wait for the home screen before giving up on it.
    ///
    /// Bounded because `homeDidLoad` is set by `HomeView`, and there are ways to
    /// launch without one on screen — signed out, or restored onto another route.
    /// Waiting forever in those cases would mean a library that never syncs, which
    /// is a far worse failure than a sync that starts eight seconds late.
    private static let homeLoadGrace: Duration = .seconds(8)

    /// Suspends until the home screen has its content, or the grace period expires.
    ///
    /// Polled rather than signalled with a continuation. The state it waits on is a
    /// plain `Bool` written from a view's `.task`, and a continuation would need
    /// storing, resuming exactly once, and cancelling on sign-out — three places for
    /// a launch to hang. A 50ms poll costs nothing against a wait this short and
    /// cannot deadlock.
    func waitForHomeLoad() async {
        guard !homeDidLoad else { return }
        let deadline = ContinuousClock.now + Self.homeLoadGrace
        while !homeDidLoad, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !homeDidLoad {
            Diagnostics.log("[launch] home did not load in time — syncing anyway")
        }
    }
}
