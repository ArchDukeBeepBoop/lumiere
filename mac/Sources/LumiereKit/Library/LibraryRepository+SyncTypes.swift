import Foundation

/// What a sync pass can be asked for, and what it reports back.
///
/// Split out of LibraryRepository+Sync.swift, which reached the project's 300-line
/// limit once the pass started reporting counts. These are the vocabulary the sync
/// panel and the sync loop share; the file next door is the algorithm.
extension LibraryRepository {

    /// How much of a library a sync actually got.
    ///
    /// The distinction earns its place: "reachable but one page timed out" and
    /// "server is down" used to be the same outcome, and the app reported both as
    /// an outage over a library that was 95% synced.
    public enum SyncOutcome: Sendable {
        case complete
        /// Some pages never loaded. Everything read is cached; nothing was deleted.
        case partial
        /// An incremental pass reached rows it had already seen and stopped. Normal
        /// and expected — kept apart from `partial` so the sync panel does not warn
        /// about a sync that did exactly what it was asked to.
        case upToDate
    }

    /// What a single library's pass did, not just how it ended.
    ///
    /// The outcome alone cannot answer the question the sync panel is most often
    /// opened to answer — "did that actually remove the titles whose files are
    /// gone?" — so the counts travel with it. `removed` is non-zero only after a
    /// pass that reached the deletion sweep, which is precisely the fact worth
    /// reporting.
    public struct SyncReport: Sendable, Equatable {
        public var outcome: SyncOutcome
        /// Distinct items the server returned during this pass.
        public var seen: Int
        /// Rows the deletion sweep removed. Zero unless the sweep ran.
        public var removed: Int
        /// Whether this pass wrote anything the cache did not already hold.
        ///
        /// Separate from the outcome, because the two answer different questions
        /// and were being conflated. An incremental pass stops when the last few
        /// pages were all familiar and reports `upToDate` — but pages *before*
        /// those may have carried new rows, and they were written. Reading
        /// "stopped early" as "nothing changed" is what left a library grid
        /// showing yesterday's answer after a sync that had just added three
        /// shows to it.
        public var wroteSomething: Bool

        public init(
            outcome: SyncOutcome, seen: Int = 0, removed: Int = 0,
            wroteSomething: Bool = false
        ) {
            self.outcome = outcome
            self.wroteSomething = wroteSomething
            self.seen = seen
            self.removed = removed
        }
    }

    /// How much of a library to read.
    public enum SyncMode: Sendable {
        /// The newest page only, then stop: a first sign-in shows the newest
        /// titles of every library in seconds, before the full reads that
        /// follow fill in the rest. Never sweeps, never counts as a full pass.
        case preview
        /// Everything, in name order, followed by the deletion sweep. The only pass
        /// that can notice a removal or an edit made on the server.
        case full
        /// Newest first, stopping once a whole page is already cached.
        ///
        /// What a routine sync should be: new episodes and new titles arrive at the
        /// top of a DateCreated-descending list, so on a 44,000-item library the
        /// usual answer is one page instead of two hundred and twenty. It cannot see
        /// deletions or server-side edits, which is what `full` is for — so it never
        /// runs the sweep and never claims to have seen the whole library.
        case incremental
    }
}
