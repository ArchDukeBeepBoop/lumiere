import SwiftUI
import LumiereKit
import AppKit

@main
struct LumiereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance: AppearanceSetting = .auto
    @AppStorage(AppIconChoice.storageKey) private var appIcon = AppIconChoice.aperture.rawValue

    @State private var app = AppModel()
    /// Carries commands down to the player, and the state the playback menus read
    /// back up. The AppKit menu controller pulls from it at the moment a menu
    /// opens, so it needs no observation — which is exactly why it replaced the
    /// scene `@State` a SwiftUI menu bar quietly ignored.
    @State private var bridge = PlayerBridge()

    init() {
        // Quit from inside the private room, its settings are still in place.
        // See `RoomPreferences`.
        RoomPreferences.recoverAtLaunch()
    }

    var body: some Scene {
        Window("Lumiere", id: "main") {
            RootView(app: app, bridge: bridge)
                // Also in the environment, not only down the initialiser chain.
                //
                // Most views take it as a property, which is fine where the parent
                // is building them anyway. It does not reach the screens the shell
                // pushes onto a `NavigationStack` from a route — genre browse, the
                // Latest grid, a person's filmography — which are constructed from
                // the route value and have no parent holding a reference. Those read
                // `@Environment(AppModel.self)`, and without this it is nil: their
                // right-click menus were built, compiled, and silently absent.
                .environment(app)
                // Which libraries are plain folders, for the cards that need to know
                // what a `Primary` image is. See `FolderLibraries`.
                .folderLibraries(app.libraries)
                .frame(minWidth: 960, minHeight: 620)
                // Applied to NSApp rather than as a SwiftUI colorScheme so that
                // menus, panels and AppKit-hosted video chrome agree with it.
                .onAppear {
                    appearance.apply()
                    // The Dock forgets a runtime icon on quit, so the choice is
                    // re-applied at every launch rather than written into the
                    // bundle — writing there would break the signature.
                    (AppIconChoice(rawValue: appIcon) ?? .aperture).apply()
                    // Installed here rather than in applicationDidFinishLaunching:
                    // SwiftUI builds the main menu after launch, so inserting any
                    // earlier means the menus are replaced out from under us.
                    appDelegate.installPlaybackMenus(bridge: bridge)
                }
                .onChange(of: appearance) { appearance.apply() }
                .onChange(of: appIcon) {
                    (AppIconChoice(rawValue: appIcon) ?? .aperture).apply()
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            AppCommands(app: app)
            LibraryCommands(app: app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Held for the app's lifetime. NSMenu does not retain an item's target, so
    /// letting this go would leave every playback menu item firing into nothing.
    @MainActor private var playbackMenus: PlaybackMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running from a .app bundle, SwiftPM binaries still launch as a
        // background-only process unless the activation policy is set.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func installPlaybackMenus(bridge: PlayerBridge) {
        guard playbackMenus == nil, let mainMenu = NSApp.mainMenu else { return }
        let controller = PlaybackMenuController(bridge: bridge)
        controller.install(into: mainMenu)
        playbackMenus = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
