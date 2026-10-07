import Foundation
import GRDB

/// Taking back a watch-state change to a whole season or show.
///
/// Marking a season is one click and twenty-five episodes; ticking the wrong
/// season, or unticking one you were halfway through, was twenty-five clicks
/// to put right — and a resume position, once cleared, was gone. A snapshot
/// taken before the change is what makes it reversible.
public struct WatchSnapshot: Sendable {
    public struct State: Sendable, Equatable {
        public let played: Bool
        public let positionTicks: Int64
    }
    public let rootId: String
    public let states: [String: State]
}

public extension LibraryRepository {

    /// The watch state of an item and everything playable under it.
    func watchSnapshot(of rootId: String) async throws -> WatchSnapshot {
        try await database.writer.read { db in
            var states: [String: WatchSnapshot.State] = [:]
            var frontier = [rootId]
            var seen: Set<String> = [rootId]
            while let parent = frontier.popLast() {
                let children = try ItemRecord
                    .filter(Column("parentId") == parent
                        || Column("seasonId") == parent
                        || Column("seriesId") == parent)
                    .filter(Column("extraType") == nil)
                    .fetchAll(db)
                    .filter { seen.insert($0.id).inserted }
                for child in children {
                    frontier.append(child.id)
                    guard UnplayedCount.counts(type: child.itemType, extraType: child.extraType)
                    else { continue }
                    let data = try UserDataRecord.fetchOne(db, key: child.id)
                    states[child.id] = .init(
                        played: data?.played ?? false,
                        positionTicks: data?.playbackPositionTicks ?? 0
                    )
                }
            }
            return WatchSnapshot(rootId: rootId, states: states)
        }
    }

    /// Puts every item back as the snapshot found it, here and on the server.
    /// Only items that differ are sent, so undoing a season where two episodes
    /// were already watched costs the twenty-three that changed.
    @discardableResult
    func restore(_ snapshot: WatchSnapshot) async -> Bool {
        let now = try? await watchSnapshot(of: snapshot.rootId)
        var ok = true
        for (id, was) in snapshot.states where now?.states[id] != was {
            try? await applyLocalProgress(
                itemId: id, positionSeconds: Double(was.positionTicks) / 10_000_000,
                played: was.played, announce: false
            )
            do {
                try await client.markPlayed(itemId: id, played: was.played)
                if !was.played, was.positionTicks > 0 {
                    // A resume position only reaches the server as a playback
                    // report, the same way clearing one does.
                    try? await client.reportPlaybackStopped(
                        itemId: id, mediaSourceId: id, playSessionId: nil,
                        positionSeconds: Double(was.positionTicks) / 10_000_000
                    )
                }
            } catch {
                ok = false
            }
        }
        try? await database.writer.write { db in
            var containers = [snapshot.rootId]
            containers += try Self.ancestors(of: snapshot.rootId, in: db)
            containers += try String.fetchAll(db, sql: """
                SELECT id FROM item WHERE (seriesId = ?1 OR parentId = ?1) AND isFolder = 1
                """, arguments: [snapshot.rootId])
            for id in Set(containers) { try Self.recountUnplayed(id, in: db) }
        }
        await adoptServerWatchState(around: snapshot.rootId)
        LibraryChangeFeed.shared.note("watch state restored", itemId: snapshot.rootId)
        return ok
    }
}
