import AppKit
import LumiereKit

/// Opening anything, the way a player is expected to: from Finder, the Dock,
/// File › Open, a drop on the window, or an address.
///
/// Everything opened becomes a local row first — see `openLocal` — so it plays
/// through the same player, with resume, Next and the queue, as anything else.
@MainActor
extension AppModel {

    /// Plays what was opened. Files that arrive before the library is ready —
    /// a double-click in Finder is what launched the app — wait in `OpenInbox`
    /// and are played by `openPending()` once it is.
    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let repository else {
            OpenInbox.shared.pending += urls
            return
        }
        Task {
            var ids: [String] = []
            for url in urls {
                do {
                    if StreamPlaylist.isStream(url) || StreamPlaylist.isPlaylist(url) {
                        ids += try await repository.openStream(url)
                    } else {
                        ids += try await repository.openLocal([url])
                    }
                    if url.isFileURL { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
                    OpenRecents.note(url)
                } catch {
                    report("Couldn’t open \(url.lastPathComponent): \(ConnectionState.message(for: error))", actionTitle: "")
                }
            }
            guard let first = ids.first else {
                if !urls.isEmpty { report("Nothing playable in what was opened.", actionTitle: "") }
                return
            }
            // Several things chosen at once: the first plays, the rest queue in
            // the order chosen. A single file needs no queue — its folder is
            // already Next and Previous.
            if urls.count > 1 {
                for id in ids.dropFirst() {
                    if let entry = try? await repository.entry(id: id) { PlayQueue.shared.add([entry]) }
                }
            }
            nowPlayingItemId = first
        }
    }

    /// Plays anything opened before the library was ready.
    func openPending() {
        let waiting = OpenInbox.shared.pending
        guard repository != nil, !waiting.isEmpty else { return }
        OpenInbox.shared.pending = []
        open(waiting)
    }

    // MARK: - Panels

    func chooseFilesToOpen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = OpenTypes.all
        panel.message = "Choose video or audio files to play."
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func chooseFolderToOpen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to play from the start."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open([url])
    }

    /// An address on the clipboard, if there is one — a copied stream link or
    /// a file copied in Finder.
    func openFromClipboard() {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            open(urls)
        } else if let text = board.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: text), StreamPlaylist.isStream(url) {
            open([url])
        } else {
            report("The clipboard holds no file or stream address.", actionTitle: "")
        }
    }
}

/// Where opened files arrive, from either door.
///
/// macOS hands a Finder double-click to the app delegate and, in a SwiftUI app,
/// sometimes to `onOpenURL` as well; the same file within a moment is one open,
/// not two. Before the window exists there is no model to hand it to, and
/// before the library is attached there is nothing to write it into — both
/// wait in `pending`.
@MainActor
final class OpenInbox {
    static let shared = OpenInbox()
    var pending: [URL] = []
    var handler: (([URL]) -> Void)?
    private var recent: [URL: Date] = [:]

    func receive(_ urls: [URL]) {
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 2 }
        let fresh = urls.filter { recent[$0] == nil }
        for url in fresh { recent[url] = now }
        guard !fresh.isEmpty else { return }
        if let handler { handler(fresh) } else { pending += fresh }
    }
}
