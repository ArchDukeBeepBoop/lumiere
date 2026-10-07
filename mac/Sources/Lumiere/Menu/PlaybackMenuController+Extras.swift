import AppKit
import LumiereKit
import LumierePlayer
import UniformTypeIdentifiers

/// The items a mature player has that the first four menus did not: moving
/// between episodes, jumping to a typed time, speed steps, flipping, a
/// screenshot, floating on top, audio and subtitle timing, loading a subtitle
/// file and its size.
///
/// Added to the menus `install` builds rather than written into them, which
/// keeps the controller readable and every addition in one place.
extension PlaybackMenuController {

    /// Tags for the items that are not player commands, so validation can
    /// tell them apart without comparing titles.
    enum ExtraTag: Int { case jumpToTime = 9101, floatOnTop, addSubtitle, miniPlayer }

    func addExtras(to menus: [NSMenu]) {
        guard menus.count == 4 else { return }
        addPlaybackExtras(menus[0])
        addVideoExtras(menus[1])
        addAudioExtras(menus[2])
        addSubtitleExtras(menus[3])
    }

    // MARK: - Playback

    private func addPlaybackExtras(_ menu: NSMenu) {
        // Above Close Player and its separator, which stay last.
        var at = max(0, menu.items.count - 2)
        func put(_ item: NSMenuItem) { menu.insertItem(item, at: at); at += 1 }

        put(.separator())
        put(menuItem("Previous Episode", .episode(forward: false),
                     key: arrow(NSLeftArrowFunctionKey), modifiers: [.command, .shift]))
        put(menuItem("Next Episode", .episode(forward: true),
                     key: arrow(NSRightArrowFunctionKey), modifiers: [.command, .shift]))
        put(menuItem("Start Over", .startOver))
        put(selectorItem("Jump to Time…", #selector(jumpToTime), .jumpToTime,
                         key: "j", modifiers: .command))
        put(menuItem("Jump Back 1 Minute", .skip(-60)))
        put(menuItem("Jump Forward 1 Minute", .skip(60)))
        put(menuItem("A-B Loop", .abLoop, key: "l", modifiers: [.command, .option]))
        put(.separator())
        put(menuItem("Stop After This Episode", .sleep(minutes: 0)))
        put(menuItem("Stop in 30 Minutes", .sleep(minutes: 30)))
        put(menuItem("Stop in 60 Minutes", .sleep(minutes: 60)))
        put(menuItem("Cancel Sleep Timer", .sleep(minutes: -1)))
        put(.separator())
        put(menuItem("Faster", .nudgeSpeed(0.25), key: "=", modifiers: .command))
        put(menuItem("Slower", .nudgeSpeed(-0.25), key: "-", modifiers: .command))
        put(menuItem("Normal Speed", .setSpeed(1), key: "0", modifiers: .command))
    }

    // MARK: - Video

    private func addVideoExtras(_ menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(menuItem("Flip Horizontally", .toggleFlip(horizontal: true)))
        menu.addItem(menuItem("Flip Vertically", .toggleFlip(horizontal: false)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Take Screenshot", .screenshot, key: "s", modifiers: [.command, .option]))
        menu.addItem(menuItem("Copy Frame", .copyFrame, key: "c", modifiers: [.command, .option]))
        menu.addItem(selectorItem("Mini Player", #selector(toggleMiniPlayer), .miniPlayer,
                                  key: "m", modifiers: [.command, .shift]))
        menu.addItem(selectorItem("Float on Top", #selector(toggleFloatOnTop), .floatOnTop,
                                  key: "f", modifiers: [.command, .option]))
    }

    // MARK: - Audio

    private func addAudioExtras(_ menu: NSMenu) {
        outputMenu.delegate = self
        let output = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        output.submenu = outputMenu
        menu.addItem(.separator())
        menu.addItem(output)
        menu.addItem(.separator())
        menu.addItem(menuItem("Audio Earlier", .nudgeAudioDelay(-1)))
        menu.addItem(menuItem("Audio Later", .nudgeAudioDelay(1)))
        menu.addItem(menuItem("Reset Audio Delay", .nudgeAudioDelay(0)))
    }

    // MARK: - Subtitles

    private func addSubtitleExtras(_ menu: NSMenu) {
        menu.insertItem(selectorItem("Add Subtitle File…", #selector(addSubtitleFile), .addSubtitle,
                                     key: "o", modifiers: [.command, .option]), at: 1)
        menu.addItem(.separator())
        menu.addItem(menuItem("Subtitles Earlier", .nudgeSubtitleDelay(-1),
                              key: "[", modifiers: [.command, .option]))
        menu.addItem(menuItem("Subtitles Later", .nudgeSubtitleDelay(1),
                              key: "]", modifiers: [.command, .option]))
        menu.addItem(menuItem("Reset Subtitle Delay", .nudgeSubtitleDelay(0)))
        menu.addItem(.separator())
        let sizes = NSMenu()
        sizes.delegate = self
        for size in SubtitleSize.allCases { sizes.addItem(menuItem(size.title, .setSubtitleSize(size))) }
        let parent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        parent.submenu = sizes
        menu.addItem(parent)
    }

    // MARK: - Titles, checks, enablement

    /// Live titles and ticks for the extras; called from `menuWillOpen`.
    func refreshExtra(_ item: NSMenuItem, _ command: PlayerCommand) {
        switch command {
        case .toggleFlip(let horizontal):
            item.state = (horizontal ? menuState.flipHorizontal : menuState.flipVertical) ? .on : .off
        case .setSubtitleSize(let size):
            item.state = menuState.subtitleSize == size ? .on : .off
        case .sleep(let minutes):
            switch SleepTimer.mode {
            case .afterEpisode: item.state = minutes == 0 ? .on : .off
            case .at: item.state = .off
            case .off: item.state = .off
            }
        case .abLoop:
            item.title = ["Set Loop Start (A)", "Set Loop End (B)", "Clear A-B Loop"][menuState.abStage]
        case .nudgeAudioDelay(0):
            item.title = "Reset Audio Delay" + Self.offset(menuState.audioDelay)
        case .nudgeSubtitleDelay(0):
            item.title = "Reset Subtitle Delay" + Self.offset(menuState.subtitleDelay)
        default: break
        }
    }

    /// Enablement for the extras; nil where the item is not one of them.
    func validateExtra(_ command: PlayerCommand) -> Bool? {
        switch command {
        case .episode(let forward):
            return forward ? menuState.hasNextEpisode : menuState.hasPreviousEpisode
        case .screenshot, .copyFrame:
            // Nothing leaves the window while the private room is open.
            if RoomChrome.isOpen && Preference.roomBlocksCapture.value { return false }
            return menuState.supportsVideoAdjustments
        case .toggleFlip, .nudgeAudioDelay, .abLoop, .setAudioDevice:
            return menuState.supportsVideoAdjustments
        case .nudgeSubtitleDelay:
            return menuState.supportsSubtitleDelay
        case .sleep(let minutes):
            return minutes >= 0 || SleepTimer.mode != .off
        default: return nil
        }
    }

    func validateExtra(tag: Int) -> Bool? {
        guard let tag = ExtraTag(rawValue: tag) else { return nil }
        switch tag {
        case .floatOnTop:
            // Useful with or without a film, so never greyed.
            return true
        case .miniPlayer:
            return menuState.isActive || MiniPlayer.isOn
        case .addSubtitle:
            return menuState.isActive && menuState.supportsVideoAdjustments
        case .jumpToTime:
            return menuState.isActive && menuState.duration > 0
        }
    }

    func refreshFloatOnTop(_ item: NSMenuItem) {
        guard item.tag == ExtraTag.floatOnTop.rawValue else { return }
        item.state = NSApp.mainWindow?.level == .floating ? .on : .off
    }

    private static func offset(_ seconds: Double) -> String {
        abs(seconds) < 0.05 ? "" : String(format: " (%+.1f s)", seconds)
    }

    // MARK: - Actions that need AppKit first

    @objc func jumpToTime() {
        let alert = NSAlert()
        alert.messageText = "Jump to Time"
        alert.informativeText = "A time such as 1:23:45 or 23:45, minutes such as 45, or a percentage such as 50%."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "1:23:45"
        alert.accessoryView = field
        alert.addButton(withTitle: "Jump")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let seconds = TimeEntry.seconds(from: field.stringValue, duration: menuState.duration) else {
            NSSound.beep()
            return
        }
        bridge.send(.seek(seconds))
    }

    @objc func toggleMiniPlayer() { MiniPlayer.toggle() }

    @objc func toggleFloatOnTop() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        window.level = window.level == .floating ? .normal : .floating
    }

    @objc func addSubtitleFile() {
        let panel = NSOpenPanel()
        panel.title = "Add Subtitle File"
        panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt", "sub", "sup"]
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bridge.send(.addSubtitleFile(url))
    }

    /// Audio › Output, built as it opens: devices come and go — headphones,
    /// an AirPlay speaker — and a list from launch would be wrong by evening.
    func rebuildOutputs(_ menu: NSMenu) {
        menu.removeAllItems()
        let system = menuItem("System Output", .setAudioDevice(nil))
        system.state = menuState.audioDeviceUID == nil ? .on : .off
        menu.addItem(system)
        menu.addItem(.separator())
        for device in AudioOutputs.all() {
            let item = menuItem(device.name, .setAudioDevice(device))
            item.state = menuState.audioDeviceUID == device.uid ? .on : .off
            menu.addItem(item)
        }
    }

    // MARK: - Helpers

    private func selectorItem(
        _ title: String, _ action: Selector, _ tag: ExtraTag,
        key: String = "", modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.tag = tag.rawValue
        return item
    }

    private func arrow(_ code: Int) -> String {
        String(UnicodeScalar(UInt32(code))!)
    }
}
