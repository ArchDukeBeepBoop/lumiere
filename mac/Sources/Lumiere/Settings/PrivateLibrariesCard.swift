import SwiftUI
import LumiereKit

/// Which libraries stay out of the places you did not ask to see them.
struct PrivateLibrariesCard: View {
    @Bindable var app: AppModel

    /// Mirrors the stored set so a toggle redraws. `AppModel.privateLibraryIds`
    /// reads UserDefaults directly, which `@Observable` cannot see into.
    @State private var selection: Set<String> = []

    private var candidates: [LibraryRecord] {
        app.libraries.filter(\.holdsPlayableVideo)
    }

    var body: some View {
        SettingsCard(
            title: "Private Libraries",
            icon: "eye.slash",
            subtitle: "Kept out of home, search and Continue Watching"
        ) {
            if candidates.isEmpty {
                SettingsNote("No libraries yet.")
            } else {
                ForEach(candidates) { library in
                    Toggle(library.name, isOn: binding(for: library.id))
                        .toggleStyle(.checkbox)
                }
            }

            SettingsNote("A ticked library disappears from the home screen, the "
                       + "spotlight, Continue Watching, Browse by Genre, search "
                       + "results and the sidebar. Nothing is deleted, nothing is "
                       + "moved, and no watch history is lost — opening the library "
                       + "still shows everything in it.")

            SettingsNote("Private Room in the sidebar opens them as a space of their "
                       + "own — only those libraries, with their own Home — until you "
                       + "leave it or press ⌃⌘H. Lumiere always starts outside it.")

            RoomSettings()

            // Said out loud rather than implied. The room's lock is Lumiere's
            // door, not the files': a feature that looks like more protection
            // than it is changes what somebody is willing to leave on screen.
            SettingsNote("The room's lock guards Lumiere, not the files. They are "
                       + "where they always were, and anyone using this Mac can reach "
                       + "them in Finder. It prevents accidents, not access.")
        }
        .resettable(SettingsDefaults.room)
        .task { selection = app.privateLibraryIds }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isPrivate in
                if isPrivate { selection.insert(id) } else { selection.remove(id) }
                app.privateLibraryIds = selection
                Task { await app.loadCachedLibraries() }
            }
        )
    }
}
