import Foundation
import GRDB

/// Libraries that stay out of sight unless you go looking for them.
///
/// Split from LibraryRepository.swift for the project's 300-line rule.
/// A media library is not a neutral list. Plenty of collections hold something
/// their owner would rather not have appear behind a shoulder — on the home
/// screen, in Continue Watching, in a search for an unrelated word, or in the
/// spotlight at the top of the app. Marking a library private takes it out of
/// every one of those *without* taking it away: browsing straight into it still
/// works, and everything in it is untouched.
///
/// Stated plainly, because the alternative implies more than is true: this is not
/// a security boundary. There is no password on it, the files are where they
/// always were, and anything with access to this machine can read them. It stops
/// accidents, which is what almost everyone actually wants.
extension LibraryRepository {

    public func setPrivateLibraryIds(_ ids: Set<String>) {
        privateLibraryIds = ids
    }

    /// Enters the private room (the private libraries' ids) or leaves it
    /// (empty). Inside, every cross-library read is limited to those
    /// libraries — the room's Home, search and Continue Watching are its own,
    /// and nothing from the rest of the library is mixed in.
    public func setRoomLibraryIds(_ ids: Set<String>) {
        roomLibraryIds = ids
    }

    /// SQL that survives NULL. `libraryId NOT IN (…)` is NULL for a row with no
    /// library — collection members, search results, anything cached outside a
    /// sync — and a NULL predicate filters the row out, which would have made
    /// marking one library private empty half the app.
    func privacyFilter() -> String? {
        if !roomLibraryIds.isEmpty {
            let list = roomLibraryIds
                .map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }
                .joined(separator: ",")
            // Episodes cached outside a sync carry no libraryId; their show does.
            return "(item.libraryId IN (\(list)) OR item.seriesId IN "
                + "(SELECT s.id FROM item s WHERE s.libraryId IN (\(list))))"
        }
        guard !privateLibraryIds.isEmpty else { return nil }
        let list = privateLibraryIds
            .map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }
            .joined(separator: ",")
        return "(item.libraryId IS NULL OR item.libraryId NOT IN (\(list)))"
    }

    /// Drops anything belonging to a private library, for lists SQL cannot filter.
    ///
    /// `privacyFilter()` covers every read built from the cache. It cannot cover a
    /// list the *server* produced — Next Up, server-side search, a performer's
    /// filmography — because those arrive as ids, are cached, and are then read back
    /// one at a time by a query that names an id and nothing else. Four such paths
    /// existed and all four leaked: the private library's next episode appeared in
    /// Next Up on the home screen, its titles faded into search results a quarter of
    /// a second after the correctly-filtered local ones, and its films were listed
    /// on the cast page of a film that was not private.
    ///
    /// One function so the next server-derived list inherits it rather than being
    /// the fifth to forget. Cheap: one query, only when something is actually
    /// private.
    ///
    /// Episodes are checked through their series as well as themselves, because an
    /// episode cached outside a library sync carries no `libraryId` of its own —
    /// `cache(items:)` says so — and would otherwise pass straight through.
    func visible(_ entries: [LibraryEntry]) async -> [LibraryEntry] {
        if !roomLibraryIds.isEmpty { return await onlyInRoom(entries) }
        guard !privateLibraryIds.isEmpty, !entries.isEmpty else { return entries }
        let hidden = privateLibraryIds

        let seriesIds = Set(entries.compactMap(\.item.seriesId))
        let hiddenSeries: Set<String>
        if seriesIds.isEmpty {
            hiddenSeries = []
        } else {
            hiddenSeries = (try? await database.writer.read { db -> Set<String> in
                let placeholders = seriesIds.map { _ in "?" }.joined(separator: ",")
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT id, libraryId FROM item WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(Array(seriesIds))
                )
                return Set(rows.compactMap { row -> String? in
                    guard let library: String = row["libraryId"], hidden.contains(library),
                          let id: String = row["id"] else { return nil }
                    return id
                })
            }) ?? []
        }

        return entries.filter { entry in
            if let library = entry.item.libraryId, hidden.contains(library) { return false }
            if let series = entry.item.seriesId, hiddenSeries.contains(series) { return false }
            return true
        }
    }

    /// In the room: keep only what belongs to its libraries, directly or
    /// through its show.
    private func onlyInRoom(_ entries: [LibraryEntry]) async -> [LibraryEntry] {
        let room = roomLibraryIds
        let seriesIds = Set(entries.compactMap(\.item.seriesId))
        let inRoomSeries: Set<String> = seriesIds.isEmpty ? [] : ((try? await database.writer.read { db -> Set<String> in
            let placeholders = seriesIds.map { _ in "?" }.joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: "SELECT id, libraryId FROM item WHERE id IN (\(placeholders))",
                                        arguments: StatementArguments(Array(seriesIds)))
            return Set(rows.compactMap { row -> String? in
                guard let library: String = row["libraryId"], room.contains(library),
                      let id: String = row["id"] else { return nil }
                return id
            })
        }) ?? [])
        return entries.filter { entry in
            if let library = entry.item.libraryId, room.contains(library) { return true }
            if let series = entry.item.seriesId, inRoomSeries.contains(series) { return true }
            return false
        }
    }
}
