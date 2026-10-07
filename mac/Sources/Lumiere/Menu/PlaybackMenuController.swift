import AppKit
import LumiereKit
import LumierePlayer

/// The Playback, Video, Audio and Subtitles menus, in AppKit.
///
/// SwiftUI's `Commands` cannot express these. A `CommandMenu` bar is rebuilt only
/// when a *focused value* changes; state pushed into scene `@State` — however
/// faithfully the player publishes it — does not re-evaluate `.commands`, so every
/// playback item stayed disabled exactly as it was at launch. That was never a
/// publishing bug: the publish loop ran correctly the whole time and logged the
/// right state. The state simply had nowhere to go.
///
/// AppKit inverts the flow, which is what makes it work: it asks
/// `validateMenuItem(_:)` when a menu opens and `menuNeedsUpdate(_:)` before a
/// submenu is shown. Nothing is pushed anywhere, so there is no stale-state
/// failure mode to design around — see `PlaybackMenuValidation.swift`.
@MainActor
final class PlaybackMenuController: NSObject, NSMenuItemValidation, NSMenuDelegate {

    let bridge: PlayerBridge

    /// Read live, every time a menu opens.
    var menuState: PlayerMenuState { bridge.menuState }

    /// Menus whose contents depend on the file. Held so `menuNeedsUpdate` can tell
    /// them apart, and rebuilt on open rather than at launch — a menu assembled
    /// once would show the previous file's tracks.
    let chapterMenu = NSMenu()
    let audioMenu = NSMenu()
    let subtitleMenu = NSMenu()
    let outputMenu = NSMenu()

    init(bridge: PlayerBridge) {
        self.bridge = bridge
        super.init()
    }

    // MARK: - Installation

    /// Inserts the four menus before Window, or at the end if it is absent.
    /// Hard-coding an index breaks as soon as SwiftUI adds or drops a menu.
    func install(into mainMenu: NSMenu) {
        let titles = mainMenu.items.map(\.title)
        let index = ["Window", "Help"]
            .compactMap { titles.firstIndex(of: $0) }
            .min() ?? mainMenu.items.count

        let menus = [makePlaybackMenu(), makeVideoMenu(), makeAudioMenu(), makeSubtitlesMenu()]
        addExtras(to: menus)
        for (offset, menu) in menus.enumerated() {
            let item = NSMenuItem()
            item.title = menu.title
            item.submenu = menu
            mainMenu.insertItem(item, at: index + offset)
        }
        Diagnostics.log("[menu] installed \(menus.count) AppKit menus at index \(index)")

        guard ProcessInfo.processInfo.environment["LUMIERE_DUMP_MENUS"] == "1" else { return }
        Task { [weak self] in
            // Dump on the transition rather than on a timer. The fixtures are only
            // a few seconds long, so a second dump at a fixed delay lands after
            // playback has already ended and reports everything disabled again —
            // which looks exactly like the bug this is meant to prove is fixed.
            self?.dumpMenuState(menus)
            while let self, !self.menuState.isActive {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self?.dumpMenuState(menus)
        }
    }

    // MARK: - Menu construction

    private func makePlaybackMenu() -> NSMenu {
        let menu = NSMenu(title: "Playback")
        menu.delegate = self

        // Bare-key shortcuts deliberately are not menu equivalents. A menu item
        // with an unmodified key equivalent fires app-wide, so plain "p" would
        // toggle playback while typing into the search field. The player owns the
        // bare keys through its own key handling; the menus take ⌘ combinations.
        menu.addItem(menuItem("Play", .togglePlayPause, key: "p", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Skip Back 15 Seconds", .skip(-15), key: "[", modifiers: .command))
        menu.addItem(menuItem("Skip Forward 15 Seconds", .skip(15), key: "]", modifiers: .command))
        menu.addItem(.separator())
        // ⌥⌘, not ⌘: plain ⌘, is Settings everywhere on a Mac, and it won.
        // The unmodified keys are the player's own — see the note above about
        // bare key equivalents firing app-wide — so the menu takes ⌘ and states
        // what "," and "." do while paused, which is otherwise undiscoverable.
        menu.addItem(menuItem(
            "Step Back One Frame", .step(frames: -1), key: ",", modifiers: [.command, .option]
        ))
        menu.addItem(menuItem(
            "Step Forward One Frame", .step(frames: 1), key: ".", modifiers: [.command, .option]
        ))

        menu.addItem(.separator())
        menu.addItem(menuItem(
            "Previous Chapter", .chapter(forward: false),
            key: arrowKey(NSLeftArrowFunctionKey), modifiers: [.command, .option]
        ))
        menu.addItem(menuItem(
            "Next Chapter", .chapter(forward: true),
            key: arrowKey(NSRightArrowFunctionKey), modifiers: [.command, .option]
        ))

        chapterMenu.delegate = self
        menu.addItem(submenu("Chapters", chapterMenu))

        menu.addItem(.separator())
        let speeds = NSMenu()
        speeds.delegate = self
        for speed in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0] {
            speeds.addItem(menuItem(
                speed == 1 ? "Normal" : String(format: "%.2f×", speed),
                .setSpeed(speed)
            ))
        }
        menu.addItem(submenu("Playback Speed", speeds))

        // QuickTime keeps Loop in View; here it belongs with the transport,
        // because what it changes is what happens when the file ends.
        menu.addItem(menuItem("Loop", .setLooping(true), key: "l", modifiers: .command))

        menu.addItem(.separator())
        // Not ⌘W. This menu is installed after File, so AppKit's key-equivalent
        // search reached File ▸ Close first — which closed the window, and with
        // applicationShouldTerminateAfterLastWindowClosed returning true, quit the
        // app. The player's own escape key is the real dismissal; this is the
        // discoverable one beside it.
        menu.addItem(menuItem(
            "Close Player", .close, key: "w", modifiers: [.command, .shift]
        ))
        return menu
    }

    private func makeVideoMenu() -> NSMenu {
        let menu = NSMenu(title: "Video")
        menu.delegate = self

        let aspects = NSMenu()
        aspects.delegate = self
        for option in AspectOverride.allCases {
            aspects.addItem(menuItem(option.title, .setAspect(option)))
        }
        menu.addItem(submenu("Aspect Ratio", aspects))

        let modes = NSMenu()
        modes.delegate = self
        for mode in UpscalingMode.allCases {
            modes.addItem(menuItem(mode.title, .setUpscaling(mode)))
        }
        menu.addItem(submenu("Upscaling", modes))

        menu.addItem(.separator())
        // Stored as "turn on"; `resolve` flips it against live state, so the item
        // toggles rather than only ever switching the feature one way.
        menu.addItem(menuItem("Ambient Mode", .setAmbientMode(true)))
        menu.addItem(menuItem(
            "Playback Stats", .setStatisticsHUD(true),
            key: "i", modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            "Enter Full Screen", .toggleFullScreen,
            key: "f", modifiers: [.command, .control]
        ))
        return menu
    }

    private func makeAudioMenu() -> NSMenu {
        let menu = NSMenu(title: "Audio")
        menu.delegate = self
        menu.addItem(menuItem(
            "Volume Up", .nudgeVolume(0.05),
            key: arrowKey(NSUpArrowFunctionKey), modifiers: .command
        ))
        menu.addItem(menuItem(
            "Volume Down", .nudgeVolume(-0.05),
            key: arrowKey(NSDownArrowFunctionKey), modifiers: .command
        ))
        menu.addItem(menuItem("Mute", .toggleMute, key: "m", modifiers: .command))
        menu.addItem(.separator())

        audioMenu.delegate = self
        menu.addItem(submenu("Audio Track", audioMenu))

        // A player setting, reachable while the thing it fixes is playing.
        //
        // Boost is the one audio control that gets changed mid-film — a quiet
        // mix, a laptop speaker — and until now it lived only in Settings, which
        // means leaving the film to find it. The default still lives there; this
        // is the same knob for the file in front of you.
        menu.addItem(.separator())
        let boosts = NSMenu()
        boosts.delegate = self
        for percent in [100.0, 125.0, 150.0, 175.0, 200.0] {
            boosts.addItem(menuItem(
                percent == 100 ? "Normal" : "\(Int(percent))%",
                .setVolumeBoost(percent)
            ))
        }
        menu.addItem(submenu("Volume Boost", boosts))
        return menu
    }

    /// The whole menu is the track list, so it is delegate-driven directly rather
    /// than wrapping a submenu one level deeper for nothing.
    private func makeSubtitlesMenu() -> NSMenu {
        let menu = NSMenu(title: "Subtitles")
        menu.delegate = self

        subtitleMenu.title = "Subtitles"
        subtitleMenu.delegate = self
        menu.addItem(submenu("Subtitle Track", subtitleMenu))

        // The look, beside the track. Which style reads best is a judgement made
        // *while* subtitles are on screen — that is when you can see that the
        // outline is too heavy or the type too small — and the only place to
        // change it was a settings pane behind the player.
        menu.addItem(.separator())
        let styles = NSMenu()
        styles.delegate = self
        for style in SubtitleStyle.all {
            styles.addItem(menuItem(style.title, .setSubtitleStyle(style.id)))
        }
        menu.addItem(submenu("Style", styles))
        return menu
    }

    // MARK: - Items

    /// One target/action for everything. The command rides along as the represented
    /// object, so there is no selector-per-item sprawl and no stringly-typed tags.
    func menuItem(
        _ title: String,
        _ command: PlayerCommand,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.representedObject = CommandBox(command)
        return item
    }

    /// The command an item carries, or nil for separators, labels and submenu
    /// parents. Lives here because `CommandBox` is private to this file.
    func command(for item: NSMenuItem) -> PlayerCommand? {
        (item.representedObject as? CommandBox)?.command
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func arrowKey(_ code: Int) -> String {
        String(UnicodeScalar(UInt32(code))!)
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = command(for: sender) else { return }
        bridge.send(resolve(command))
    }

    private func resolve(_ command: PlayerCommand) -> PlayerCommand {
        switch command {
        case .setAmbientMode: return .setAmbientMode(!menuState.ambientMode)
        case .setLooping: return .setLooping(!menuState.isLooping)
        case .setStatisticsHUD: return .setStatisticsHUD(!menuState.showsStatisticsHUD)
        default: return command
        }
    }
}

/// `representedObject` needs a class, and a bare enum is not one.
private final class CommandBox {
    let command: PlayerCommand
    init(_ command: PlayerCommand) { self.command = command }
}
