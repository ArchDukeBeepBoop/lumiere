import Foundation
import GRDB

/// Whether a library's items should carry the files Jellyfin merged into them.
///
/// Split from LibraryRepository+Sync.swift for the project's 300-line limit. See
/// `ItemVersionRecord` for what the merge does to a folder library.
extension LibraryRepository {

    /// Whether this library's items should carry their alternate files.
    ///
    /// Folder libraries only — the ones Jellyfin was never told are films or shows,
    /// so it neither scrapes them nor should be merging their folders. See
    /// `ItemVersionRecord` for what the merge does and `Fields.listWithVersions` for
    /// why this is not simply always on.
    /// Not private: the page loop in LibraryRepository+Sync.swift asks it once per
    /// library, and Swift's `private` is file-scoped.
    func wantsVersions(libraryId: String) async -> Bool {
        let type: String?? = try? await database.writer.read { db in
            try LibraryRecord.fetchOne(db, key: libraryId)?.collectionType
        }
        return (type ?? nil) == nil
    }

    /// Whether this library still owes a pass that collects its merged files.
    ///
    /// A one-time backfill, and it is needed because the two mechanisms miss each
    /// other exactly. `MediaSources` is only asked for on a folder library, and an
    /// incremental pass stops as soon as it recognises a page — so on a library that
    /// was already fully cached before this existed, every page is recognised, the
    /// pass stops after two, and no item ever gains its versions. Observed precisely
    /// that: `finished 3D — upToDate, 300 seen` and not one version row.
    ///
    /// The marker is per library and written only after a pass that actually walked
    /// it, so an interrupted backfill is retried rather than assumed done.
    public func needsVersionBackfill(libraryId: String) async -> Bool {
        guard await wantsVersions(libraryId: libraryId) else { return false }
        let done = try? await syncState(key: Self.versionBackfillKey(libraryId))
        return (done ?? nil) == nil
    }

    static func versionBackfillKey(_ libraryId: String) -> String {
        "library.versions.\(libraryId)"
    }

    /// Stamps what a completed pass earns the library.
    ///
    /// Three markers, deliberately separate: when it was last read at all, when it
    /// was last read *fully* — only a full pass can claim the cache matches the
    /// server — and whether that pass carried the merged files.
    func recordPassCompleted(libraryId: String, carriedVersions: Bool) async throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
        try await setSyncState(key: "library.\(libraryId)", value: stamp)
        // Only a full pass can claim the cache matches the server; routine syncs
        // read this to decide whether one is overdue.
        try await setSyncState(key: "library.full.\(libraryId)", value: stamp)
        // Only after a pass that carried them, so an interrupted backfill runs again.
        if carriedVersions {
            try await setSyncState(key: Self.versionBackfillKey(libraryId), value: stamp)
        }
    }
}
