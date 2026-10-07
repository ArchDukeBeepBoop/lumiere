import Foundation

/// A broadcast that something in the cache changed.
///
/// The fourth attempt at "the home screen does not update", and the first one that
/// is not a list of call sites to keep in step. `AppModel.contentDidChange` already
/// argued that the refresh belongs with the *write* rather than with each surface
/// that triggers one — but it was still wired by hand, and only five places ever
/// called it. Meanwhile thirty places write watch state: every right-click menu, the
/// detail page, the batch bars, the folder walls, search. Every one of them was a
/// way to change what belongs in Continue Watching without Continue Watching hearing
/// about it.
///
/// So the announcement moves into `LibraryRepository`'s own write paths. Nothing has
/// to remember to post it, a new surface inherits it, and the failure mode this has
/// had four times — a caller that forgot — is no longer possible.
///
/// An actor rather than `NotificationCenter` because the writes happen inside an
/// actor and the listener is `@MainActor`: a typed `AsyncStream` crosses that
/// boundary without an `@unchecked Sendable` anywhere.
/// What changed, and where.
///
/// The id is the point of carrying anything at all. A page holding a paged grid
/// cannot answer "something changed" by re-querying from offset zero — that
/// throws away the reader's place, which is a worse bug than the stale tick it
/// fixes. Given the id it can re-read one row and leave the rest alone. Nil where
/// the change is not about one item — clearing the whole hidden list, say — and
/// then a listener has no choice but to reload.
public struct LibraryChange: Sendable, Equatable {
    public let reason: String
    public let itemId: String?
    /// Which library changed, where the change is about a whole library rather
    /// than one row — a sync pass that wrote something.
    ///
    /// Carried for the same reason the id is: a page showing one library can
    /// ignore a pass over a different one, and reloading a grid costs the reader
    /// their place. With both nil the change is library-wide and a listener has
    /// to decide for itself.
    public let libraryId: String?

    public init(reason: String, itemId: String?, libraryId: String? = nil) {
        self.reason = reason
        self.itemId = itemId
        self.libraryId = libraryId
    }
}

public actor LibraryChangeFeed {

    /// One feed. The repository is constructed in several places — the app, the
    /// previews, the tests — and a per-repository feed would mean handing every
    /// caller a subscription it does not want.
    public static let shared = LibraryChangeFeed()

    private var continuations: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]

    /// Everything that changes from now on. Ends when the caller stops iterating.
    public func events() -> AsyncStream<LibraryChange> {
        // `makeStream` rather than the closure initialiser: that closure is
        // `@escaping` and non-isolated, so it cannot touch the dictionary above.
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream(
            // Newest wins, and one is enough. Marking forty episodes watched posts
            // forty times; a listener that is mid-refresh needs to know there is
            // more to do, not to replay each write in turn.
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.forget(id) }
        }
        return stream
    }

    private func forget(_ id: UUID) {
        continuations[id] = nil
    }

    /// Says what changed, for the log at the other end.
    public func post(_ change: LibraryChange) {
        for continuation in continuations.values {
            continuation.yield(change)
        }
    }

    /// The same, for a caller that cannot await — a repository method already deep
    /// in its own actor, which must not block its write on a listener.
    public nonisolated func note(
        _ reason: String, itemId: String? = nil, libraryId: String? = nil
    ) {
        Task { await post(LibraryChange(reason: reason, itemId: itemId, libraryId: libraryId)) }
    }
}
