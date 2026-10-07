import Foundation
import TestKit
import LumiereKit
import GRDB

/// The queue that carries offline watch progress back to the server.
///
/// Pinned because the failure it prevents is silent and destroys data: watching
/// offline wrote a position into the cache and nowhere else, and the next sync
/// pulled the server's stale value down over it. The evening was not merely
/// unshared — it was gone.
@MainActor
func registerPlaybackOutboxTests(_ t: TestRunner) async {

    func makeRepository() throws -> (LibraryRepository, LibraryDatabase) {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!,
            serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        let client = JellyfinClient(session: session, token: "t")
        return (LibraryRepository(database: database, client: client), database)
    }

    await t.suite("Playback outbox") { t in

        await t.test("a queued position comes back out") {
            let (repository, _) = try makeRepository()
            try await repository.enqueuePlayback(
                itemId: "ep1", positionSeconds: 1234, played: false, mediaSourceId: "src"
            )
            let pending = try await repository.pendingPlayback()
            t.expectEqual(pending.count, 1)
            t.expectEqual(pending.first?.itemId, "ep1")
            t.expectEqual(pending.first?.positionSeconds, 1234)
            t.expectEqual(pending.first?.mediaSourceId, "src")
        }

        await t.test("one row per title, holding the newest position") {
            // Ten-second reports over a two-hour film would otherwise queue 720 rows
            // to say one thing.
            let (repository, _) = try makeRepository()
            for seconds in [10.0, 20.0, 30.0] {
                try await repository.enqueuePlayback(
                    itemId: "ep1", positionSeconds: seconds,
                    played: false, mediaSourceId: "src"
                )
            }
            let pending = try await repository.pendingPlayback()
            t.expectEqual(pending.count, 1)
            t.expectEqual(pending.first?.positionSeconds, 30)
        }

        await t.test("clearing takes only what was actually sent") {
            // Playback carries on while a flush is in flight. Deleting by item alone
            // would throw away the newer position that arrived meanwhile.
            let (repository, _) = try makeRepository()
            try await repository.enqueuePlayback(
                itemId: "ep1", positionSeconds: 100, played: false, mediaSourceId: "src"
            )
            let sent = try await repository.pendingPlayback().first!.positionTicks

            try await repository.enqueuePlayback(
                itemId: "ep1", positionSeconds: 160, played: false, mediaSourceId: "src"
            )
            try await repository.clearPendingPlayback(itemId: "ep1", sentTicks: sent)

            let pending = try await repository.pendingPlayback()
            t.expectEqual(pending.count, 1, "the newer position must survive the flush")
            t.expectEqual(pending.first?.positionSeconds, 160)
        }

        await t.test("clearing the position that was sent empties the queue") {
            let (repository, _) = try makeRepository()
            try await repository.enqueuePlayback(
                itemId: "ep1", positionSeconds: 100, played: false, mediaSourceId: "src"
            )
            let sent = try await repository.pendingPlayback().first!.positionTicks
            try await repository.clearPendingPlayback(itemId: "ep1", sentTicks: sent)
            t.expectEqual(try await repository.pendingPlaybackCount(), 0)
        }

        await t.test("oldest first, so the last write is the one that stands") {
            let (repository, _) = try makeRepository()
            try await repository.enqueuePlayback(
                itemId: "first", positionSeconds: 10, played: false, mediaSourceId: nil
            )
            try await Task.sleep(for: .milliseconds(20))
            try await repository.enqueuePlayback(
                itemId: "second", positionSeconds: 20, played: false, mediaSourceId: nil
            )
            let pending = try await repository.pendingPlayback()
            t.expectEqual(pending.map(\.itemId), ["first", "second"])
        }
    }
}
