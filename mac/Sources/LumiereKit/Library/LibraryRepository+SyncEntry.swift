import Foundation
import GRDB

/// The public way into a library sync. Split from LibraryRepository+Sync.swift
/// for the 300-line rule; the pass itself is `performLibrarySync` there.
extension LibraryRepository {

    /// Pulls every item in a library, one page at a time.
    ///
    /// Pages are written as they arrive rather than accumulated: a 5,000-item
    /// library must never be fully resident, which is the whole reason the cache
    /// exists. `onProgress` reports (synced, total) for the UI.
    /// Wraps the pass below so `refreshContentDates` runs whichever way it ends.
    ///
    /// It cannot be a `defer` — that block cannot await — and it must not be a
    /// single call at the bottom, which is what it was and why it did nothing.
    /// Saving an item writes `contentDate` as the row's own date, so every page
    /// this pass writes *clobbers* the series ranking the migration computed; the
    /// refresh at the end put it back, but three of the four ways out of the pass
    /// return before reaching it. The incremental path is one of them, and it is
    /// the one that runs on almost every launch — so the Anime shelf was recomputed
    /// correctly and then flattened again a few seconds later, every time.
    ///
    /// Also on the throwing path: a sync that failed halfway still wrote pages, and
    /// leaving those rows ranked by their folder date is the bug this exists to fix.
    @discardableResult
    public func syncLibrary(
        id libraryId: String,
        mode: SyncMode = .full,
        pageSize: Int = 200,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> SyncReport {
        do {
            let report = try await performLibrarySync(
                id: libraryId, mode: mode, pageSize: pageSize, onProgress: onProgress
            )
            try await refreshContentDates(libraryId: libraryId)
            return report
        } catch {
            try? await refreshContentDates(libraryId: libraryId)
            throw error
        }
    }
}
