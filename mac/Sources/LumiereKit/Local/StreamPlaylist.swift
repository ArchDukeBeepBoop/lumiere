import Foundation
import GRDB

/// Network streams and .m3u playlists, opened by address.
///
/// A stream is written as a local row whose path is its address, so it gets
/// resume, the queue and Next like a file does; `localFile(for:)` hands the
/// address to mpv unchanged. A playlist becomes a folder row with one row per
/// entry, so Next walks the channels in the order the list gives them.
public enum StreamPlaylist {

    public struct Entry: Equatable, Sendable {
        public let title: String
        public let url: URL
    }

    /// The schemes mpv opens by address. Anything else is not a stream.
    public static let schemes: Set<String> = ["http", "https", "rtsp", "rtmp", "rtp", "udp", "mms", "srt"]

    public static func isStream(_ url: URL) -> Bool {
        schemes.contains(url.scheme?.lowercased() ?? "")
    }

    public static func isPlaylist(_ url: URL) -> Bool {
        ["m3u", "m3u8"].contains(url.pathExtension.lowercased()) && !isHLS(url)
    }

    /// An .m3u8 on a server is usually HLS — a single stream mpv plays itself,
    /// not a list of channels. Read only as a list when it is a file on disk.
    static func isHLS(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" && isStream(url)
    }

    /// The entries of an extended or plain M3U, in order.
    ///
    /// `#EXTINF:-1 tvg-id="x" group-title="News",Channel Name` gives the title
    /// after the last comma outside quotes; a line with no EXTINF before it is
    /// titled by its own address. Relative entries resolve against `base`.
    public static func parse(_ text: String, base: URL? = nil) -> [Entry] {
        var entries: [Entry] = []
        var pendingTitle: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.uppercased().hasPrefix("#EXTINF") {
                pendingTitle = title(fromExtinf: line)
                continue
            }
            if line.hasPrefix("#") { continue }
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL
                    ?? URL(string: line.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "")
            else { pendingTitle = nil; continue }
            let fallback = url.deletingPathExtension().lastPathComponent
            let name = pendingTitle.flatMap { $0.isEmpty ? nil : $0 }
                ?? (fallback.isEmpty ? url.absoluteString : fallback)
            entries.append(Entry(title: name, url: url))
            pendingTitle = nil
        }
        return entries
    }

    static func title(fromExtinf line: String) -> String {
        var inQuotes = false
        var lastComma: String.Index?
        for index in line.indices {
            switch line[index] {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes: lastComma = index
            default: break
            }
        }
        guard let lastComma else { return "" }
        return line[line.index(after: lastComma)...].trimmingCharacters(in: .whitespaces)
    }
}

public extension LibraryRepository {

    /// Writes rows for a stream or a playlist and returns the ids to play.
    func openStream(_ url: URL, title: String? = nil) async throws -> [String] {
        let entries: [StreamPlaylist.Entry]
        var listName: String?
        if StreamPlaylist.isPlaylist(url), let data = try await Self.playlistData(url) {
            entries = StreamPlaylist.parse(String(decoding: data, as: UTF8.self), base: url)
            listName = title ?? url.deletingPathExtension().lastPathComponent
        } else {
            entries = [.init(title: title ?? Self.streamTitle(url), url: url)]
        }
        guard !entries.isEmpty else { return [] }

        let parentId = listName.map { _ in LocalLibrary.id(for: "playlist:" + url.absoluteString) }
        var rows: [ItemRecord] = []
        if let listName, let parentId { rows.append(Self.streamRow(id: parentId, name: listName, path: nil, parentId: nil)) }
        for (position, entry) in entries.enumerated() {
            var row = Self.streamRow(
                id: LocalLibrary.id(for: "stream:" + entry.url.absoluteString),
                name: entry.title, path: entry.url.absoluteString, parentId: parentId
            )
            // The list's own order, which Next follows. See `localSiblings`.
            row.indexNumber = position + 1
            rows.append(row)
        }
        let ids = rows.filter { !$0.isFolder }.map(\.id)
        let toSave = rows
        try await database.writer.write { db in
            try LibraryRecord(
                id: LocalLibrary.openedLibraryId, serverId: LocalLibrary.serverId,
                name: "Opened Files", collectionType: nil, sortIndex: 2_000, itemCount: 0
            ).save(db)
            for row in toSave { try row.save(db) }
        }
        return ids
    }

    /// A list's text. A remote list this app may not fetch — App Transport
    /// Security refuses plain http — is nil, and the address goes to mpv as
    /// one stream: mpv reads the list itself and plays it in order, without
    /// the channel names in Lumiere's queue.
    private static func playlistData(_ url: URL) async throws -> Data? {
        if url.isFileURL { return try Data(contentsOf: url) }
        do {
            return try await URLSession.shared.data(from: url).0
        } catch {
            Diagnostics.log("[open] \(url.host ?? "playlist") not fetched (\(error.localizedDescription)); mpv will read it")
            return nil
        }
    }

    private static func streamTitle(_ url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        return last.isEmpty || last == "/" ? (url.host ?? url.absoluteString) : last
    }

    private static func streamRow(id: String, name: String, path: String?, parentId: String?) -> ItemRecord {
        var item = ItemRecord(
            id: id, serverId: LocalLibrary.serverId, type: path == nil ? "Folder" : "Video",
            name: name, sortName: ItemRecord.normalizedTitle(name),
            searchKey: SearchKey.normalize(name), isFolder: path == nil, syncedAt: Date()
        )
        item.parentId = parentId
        item.libraryId = LocalLibrary.openedLibraryId
        item.path = path
        item.setDateCreated(Date())
        return item
    }
}
