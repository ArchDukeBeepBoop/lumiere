import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LumiereKit

/// What was opened lately, newest first, for the On This Computer page.
///
/// Addresses only — files and streams — in this Mac's defaults, and only while
/// Settings › On This Computer › Remember Recent Files is on. Turning it off
/// clears the list, so switching it off is also how to forget.
@MainActor
enum OpenRecents {
    static let key = "openRecents"
    static let limit = 40

    static var all: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(URL.init(string:))
    }

    static func note(_ url: URL) {
        guard Preference.remembersRecentFiles.value else { return }
        var list = all.filter { $0 != url }
        list.insert(url, at: 0)
        UserDefaults.standard.set(list.prefix(limit).map(\.absoluteString), forKey: key)
        NotificationCenter.default.post(name: .openRecentsChanged, object: nil)
    }

    static func forget(_ url: URL) {
        UserDefaults.standard.set(all.filter { $0 != url }.map(\.absoluteString), forKey: key)
        NotificationCenter.default.post(name: .openRecentsChanged, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NSDocumentController.shared.clearRecentDocuments(nil)
        NotificationCenter.default.post(name: .openRecentsChanged, object: nil)
    }
}

extension Notification.Name {
    static let openRecentsChanged = Notification.Name("lumiere.openRecentsChanged")
}

/// The content types File › Open and the Finder's Open With accept.
enum OpenTypes {
    static let all: [UTType] = [.movie, .video, .audio, .audiovisualContent, .m3uPlaylist]
        + LocalLibrary.playableExtensions.compactMap { UTType(filenameExtension: $0) }
}

extension Notification.Name {
    /// File › Open Address…, answered by the On This Computer page.
    static let askOpenAddress = Notification.Name("lumiere.askOpenAddress")
}

/// File › Open Recent, from `OpenRecents` so streams are listed too.
struct OpenRecentMenu: View {
    let app: AppModel
    @State private var recents: [URL] = OpenRecents.all

    var body: some View {
        Menu("Open Recent") {
            ForEach(recents.prefix(15), id: \.self) { url in
                Button(ComputerRecentList.title(for: url)) { app.open([url]) }
            }
            if !recents.isEmpty { Divider() }
            Button("Clear Menu") { OpenRecents.clear() }.disabled(recents.isEmpty)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentsChanged)) { _ in
            recents = OpenRecents.all
        }
    }
}
