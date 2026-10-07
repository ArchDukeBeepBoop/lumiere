import SwiftUI
import LumiereKit

/// The View menu: the library settings worth reaching without opening Settings.
///
/// These four are the ones that get changed while looking at something — you
/// switch to Light because the room did, or to filenames because a folder's
/// metadata titles are useless — and each one currently costs a trip to a pane
/// and back. A menu is the Mac's answer to that, and unlike the playback menus
/// these are plain preferences with no player state behind them, so SwiftUI can
/// express them: `@AppStorage` is a `DynamicProperty`, so the bar re-evaluates
/// when one changes and the checkmarks stay honest.
///
/// Deliberately not everything in Settings. A menu that mirrors a settings pane
/// is a second place to maintain and a longer menu to read; what belongs here is
/// what you would otherwise interrupt yourself to go and change.
struct LibraryCommands: Commands {
    let app: AppModel

    @AppStorage("appearance") private var appearance: AppearanceSetting = .auto
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle
    @AppStorage("showsUnwatchedBadges") private var showsUnwatchedBadges = true
    @AppStorage("glassBackground") private var isGlass = true
    @AppStorage(PaperTheme.storageKey) private var theme = "standard"
    @AppStorage(ChromeStyle.storageKey) private var chromeStyle = ChromeStyle.liquid

    var body: some Commands {
        // Into the system's own View menu. `CommandMenu("View")` made a second
        // menu of the same name beside it — SwiftUI always creates View for the
        // toolbar and full-screen items, so there were two in the bar.
        CommandGroup(before: .toolbar) {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }

            Picker("Titles", selection: $titleStyle) {
                ForEach(TitleStyle.allCases) { Text($0.title).tag($0) }
            }

            Picker("Theme", selection: $theme) {
                Text("Standard").tag("standard")
                Text("Paper").tag(PaperTheme.paper)
            }
            // One key to flip between the two, for reading in a bright room.
            // A fixed label: menu commands are not reliably rebuilt when a
            // stored value changes (see CLAUDE.md), and a label naming the wrong
            // theme is worse than one naming neither.
            Button("Switch Theme") {
                theme = theme == PaperTheme.paper ? "standard" : PaperTheme.paper
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            Toggle("Liquid Glass Controls", isOn: Binding(
                get: { chromeStyle == .liquid },
                set: { chromeStyle = $0 ? .liquid : .solid }
            ))

            Divider()

            Toggle("Unwatched Badges", isOn: $showsUnwatchedBadges)
            Toggle("Translucent Background", isOn: $isGlass)

            Divider()

            // The two library destinations the toolbar group does not carry.
            // Home, Search and Favourites keep their own shortcuts there.
            Button("Library Settings…") { app.pendingRoute = .settings }
                .keyboardShortcut(",", modifiers: [.command, .shift])

            Divider()
        }
    }
}
