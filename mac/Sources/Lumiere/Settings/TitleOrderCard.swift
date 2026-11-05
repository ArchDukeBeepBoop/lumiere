import SwiftUI
import LumiereKit

/// Settings › Look › Title Order: which name each library's titles go by,
/// and which sits under it on a title's page.
struct TitleOrderCard: View {
    let libraries: [LibraryRecord]
    var onChange: () -> Void = {}
    /// Bumped on a change, so the pickers reread the stored orders.
    @State private var revision = 0

    var body: some View {
        SettingsCard(title: "Title Order", icon: "textformat.abc",
                     subtitle: "What each library's titles are called") {
            SettingsNote("A library named the way you know it can go by its folder names, with the romaji under them on a title's page. Romaji comes from AniList — turn the library on under Library › Anime Franchises. Its franchise collections are named the same way: by the folder name they share, else romaji, English last.")
            ForEach(libraries.filter { $0.holdsPlayableVideo }) { library in
                SettingsRow(label: library.name) {
                    Picker("", selection: Binding(
                        get: { _ = revision; return LibraryTitleOrder.order(for: library.id) },
                        set: { LibraryTitleOrder.set($0, for: library.id); revision += 1; onChange() }
                    )) {
                        ForEach(LibraryTitleOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
            }
        }
    }
}
