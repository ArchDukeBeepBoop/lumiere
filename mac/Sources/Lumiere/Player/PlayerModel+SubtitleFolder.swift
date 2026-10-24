import AppKit
import LumiereKit

/// Subtitles for a season at once: choose the files, see each matched to its
/// episode, correct any, and every episode plays with its own from then on.
@MainActor
extension PlayerModel {

    /// The episodes a batch of subtitles is for: this season or folder, or
    /// this file alone.
    func subtitleScope() async -> [LibraryEntry] {
        if !queue.isEmpty { return queue }
        return (try? await repository.entry(id: itemId)).map { [$0] } ?? []
    }

    /// Asks for subtitle files or a folder of them; returns the files found.
    func chooseSubtitleFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose subtitle files, or the folder they’re in."
        guard panel.runModal() == .OK else { return [] }
        var found: [URL] = []
        for url in panel.urls {
            if url.hasDirectoryPath {
                let inside = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                found += inside.filter(SubtitleMatcher.isSubtitle)
            } else if SubtitleMatcher.isSubtitle(url) {
                found.append(url)
            }
        }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func filename(of entry: LibraryEntry) -> String {
        entry.item.path.map { ($0 as NSString).lastPathComponent } ?? entry.item.name
    }

    /// Saves the chosen pairs and, for the episode on screen, adds its
    /// subtitle now.
    func applySubtitleLinks(_ links: [String: URL]) async {
        for (id, url) in links { SubtitleLinks.link(url, to: id) }
        if let mine = links[itemId] {
            _ = await engineRef?.addSubtitle(url: mine, title: mine.deletingPathExtension().lastPathComponent, language: "")
            await refreshTracks()
        }
        say(links.count == 1 ? "Subtitles added" : "Subtitles added to \(links.count) episodes")
    }

    /// At load: this item's linked files, where they still exist.
    func loadLinkedSubtitles() async {
        guard let engine = engineRef, engine.supportsSubtitleDelay else { return }
        for url in SubtitleLinks.files(for: itemId).reversed()
        where FileManager.default.fileExists(atPath: url.path) {
            _ = await engine.addSubtitle(url: url, title: url.deletingPathExtension().lastPathComponent, language: "")
        }
    }
}
