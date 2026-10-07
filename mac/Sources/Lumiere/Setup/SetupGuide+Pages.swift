import SwiftUI
import LumiereKit

/// The guide's first three steps. Split from SetupGuide.swift for the
/// 300-line rule.
extension SetupGuide {
    var welcomePage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SetupHeading(title: "Welcome to Lumiere",
                         detail: "Your films, shows and music, from your own disks, on your Mac, phone and TV. A few minutes here and your library is ready.")
            point("books.vertical", "Add your libraries",
                  "Point Lumiere at the folders that hold your media. Nothing is moved, renamed or uploaded.")
            point("door.left.hand.open", "Choose your rooms",
                  "Keep some libraries in a Private Room that stays out of sight until you open it.")
            point("photo.on.rectangle", "Fill in the details",
                  "Posters, synopses, cast and collections come from The Movie Database.")
            point("slider.horizontal.3", "Make it yours",
                  "A handful of choices now. Everything else, and everything here, lives in Settings.")
        }
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            SettingsIconChip(icon, size: 30, isProminent: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.body.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
                Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var librariesPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeading(title: "Add your libraries",
                         detail: "A library is a shelf of one kind of thing — Films, TV Shows, Anime, Music — fed by one or more folders. Lumiere reads the folders, scans them, and keeps watching for anything new.")
            ServerLibraryEditor(app: app, showsRoom: false)
            SettingsNote("Tip: name files the usual way — “Film Title (2019).mkv”, “Show/Season 1/Show S01E01.mkv” — and Lumiere matches them on its own. Folders on this Mac only, without the server, can be added later under Settings › Library.")
                .padding(.top, Theme.Space.lg)
        }
    }

    var roomsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupHeading(title: "Choose your rooms",
                         detail: "Lumiere has two rooms. The Main Room is what anyone sees. The Private Room holds the libraries you’d rather keep to yourself: they stay off Home, search and Continue Watching until you open the room from the sidebar.")
            SetupRoomsList(app: app)
        }
    }
}

/// Each library with a switch for the Private Room, and the room's own locks.
struct SetupRoomsList: View {
    let app: AppModel
    @State private var libraries: [ServerLibrary] = []
    @AppStorage(Preference.roomRequiresUnlock.name) private var unlock = Preference.roomRequiresUnlock.defaultValue
    @AppStorage(Preference.roomBlursCovers.name) private var blur = Preference.roomBlursCovers.defaultValue
    @AppStorage(Preference.looksUpPrivateLibraries.name) private var lookUp = Preference.looksUpPrivateLibraries.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if libraries.isEmpty {
                SettingsNote("Add a library first, then choose its room here.")
            }
            ForEach(libraries) { library in
                Toggle(isOn: Binding(
                    get: { app.privateLibraryIds.contains(library.id) },
                    set: { on in
                        var ids = app.privateLibraryIds
                        if on { ids.insert(library.id) } else { ids.remove(library.id) }
                        app.privateLibraryIds = ids
                    })) {
                    Label(library.name, systemImage: (LibraryKind(rawValue: library.collectionType) ?? .folders).icon)
                }
                .toggleStyle(.switch)
            }
            Divider().padding(.vertical, Theme.Space.sm)
            Text("The Private Room").font(Theme.Font.cardTitle)
            Toggle("Ask for Touch ID or your password to open it", isOn: $unlock)
            Toggle("Blur its posters until you point at them", isOn: $blur)
            Toggle("Look its titles up on The Movie Database", isOn: $lookUp)
            SettingsNote("Each room keeps its own look and settings. These, and the rest, are in Settings › Privacy.")
        }
        .task { libraries = (try? await app.client?.serverLibraries()) ?? [] }
    }
}
