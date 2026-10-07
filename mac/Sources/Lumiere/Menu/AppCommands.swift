import SwiftUI

/// What is left of the menu bar in SwiftUI.
///
/// The Playback, Video, Audio and Subtitles menus used to live here and no longer
/// do: `CommandMenu` is re-evaluated only when a focused value changes, so their
/// items could never enable once playback started. They are built in AppKit now —
/// see `PlaybackMenuController`. Only what SwiftUI handles correctly is left.
struct AppCommands: Commands {
    let app: AppModel

    var body: some Commands {
        // The default New/Open items make no sense for a media client and their
        // shortcuts collide with playback bindings.
        // In their place, the two things a media client's File menu is for.
        CommandGroup(replacing: .newItem) {
            Button("Refresh Library") { app.startSync(userInitiated: true) }
                .keyboardShortcut("r", modifiers: .command)
            // The results arrive by themselves: the change watch sees the
            // server's marker move when the scan adds anything.
            Button("Scan Server for New Files") {
                Task { try? await app.client?.refreshServerLibrary() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) { HelpCommands() }

        // The quick hide: stop, leave the private room, go Home. For someone
        // walking in — faster and surer than closing the player and navigating.
        CommandGroup(after: .windowArrangement) {
            Button("Hide Now") { Task { await app.hideNow() } }
                .keyboardShortcut("h", modifiers: [.control, .command])
        }

        // ⌘, where every Mac app has it. This is a `Window` scene rather than a
        // `Settings` one — Settings is a sidebar section here, not a separate
        // window — so the standard item does not exist and had to be made.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { app.pendingRoute = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Search") { app.pendingRoute = .search }
                .keyboardShortcut("f", modifiers: .command)
            Button("Home") { app.pendingRoute = .home }
                .keyboardShortcut("1", modifiers: .command)
            Button("Favourites") { app.pendingRoute = .favourites }
                .keyboardShortcut("2", modifiers: .command)
            // ⌘3 to ⌘9: the libraries, in the order the pill lists them.
            ForEach(Array(app.visibleLibraries.prefix(7).enumerated()), id: \.element.id) { index, library in
                Button(library.name) { app.pendingRoute = .library(id: library.id, name: library.name) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 3))), modifiers: .command)
            }
            Divider()
            Button("Back") { NotificationCenter.default.post(name: .goBack, object: nil) }
                .keyboardShortcut("[", modifiers: .command)
        }
    }
}
