import AppKit
import LumiereKit
import LumierePlayer

/// Enablement, checkmarks and the file-dependent submenus.
///
/// All three are computed when the menu opens rather than pushed ahead of time,
/// which is the entire reason this menu bar works where the SwiftUI one did not.
extension PlaybackMenuController {

    // MARK: - Enablement

    /// Called by AppKit for every item as a menu opens.
    ///
    /// Nothing playing means everything is unavailable: an enabled item that does
    /// nothing is worse than one visibly greyed out.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let extra = validateExtra(tag: item.tag) { return extra }
        guard let command = command(for: item) else { return menuState.isActive }
        guard menuState.isActive else { return false }
        if let extra = validateExtra(command) { return extra }

        switch command {
        case .setAspect, .setUpscaling:
            // Only mpv can do these; AVPlayer has no equivalent, so the items go
            // grey rather than silently doing nothing on the AVFoundation path.
            return menuState.supportsVideoAdjustments
        default:
            return true
        }
    }

    /// Titles and checkmarks that depend on live state. AppKit calls this for the
    /// static menus just before they are displayed.
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            refreshFloatOnTop(item)
            guard let command = command(for: item) else { continue }
            refreshExtra(item, command)
            switch command {
            case .togglePlayPause:
                item.title = menuState.isPlaying ? "Pause" : "Play"
            case .toggleMute:
                item.title = menuState.isMuted ? "Unmute" : "Mute"
            case .setSpeed(let speed):
                item.state = abs(menuState.playbackSpeed - speed) < 0.001 ? .on : .off
            case .setAspect(let option):
                item.state = menuState.aspectOverride == option ? .on : .off
            case .setUpscaling(let mode):
                item.state = menuState.upscaling == mode ? .on : .off
            case .setAmbientMode:
                item.state = menuState.ambientMode ? .on : .off
            case .setStatisticsHUD:
                item.state = menuState.showsStatisticsHUD ? .on : .off
            case .setVolumeBoost(let percent):
                item.state = abs(menuState.volumeBoost - percent) < 0.001 ? .on : .off
            case .setSubtitleStyle(let id):
                item.state = menuState.subtitleStyleId == id ? .on : .off
            case .setLooping:
                item.state = menuState.isLooping ? .on : .off
            default:
                break
            }
        }
    }

    // MARK: - Dynamic submenus

    /// Chapters and track lists change per file, so they are built on open. A menu
    /// assembled once at launch would show the previous file's tracks.
    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu {
        case chapterMenu: rebuildChapters(menu)
        case audioMenu: rebuildAudioTracks(menu)
        case subtitleMenu: rebuildSubtitleTracks(menu)
        case outputMenu: rebuildOutputs(menu)
        default: menuWillOpen(menu)
        }
    }

    private func rebuildChapters(_ menu: NSMenu) {
        menu.removeAllItems()
        guard !menuState.chapters.isEmpty else {
            menu.addItem(disabled("No chapters"))
            return
        }
        for (index, chapter) in menuState.chapters.enumerated() {
            let name = chapter.name ?? "Chapter \(index + 1)"
            let title = "\(PlayerModel.timecode(chapter.startSeconds))  \(name)"
            menu.addItem(menuItem(title, .seek(chapter.startSeconds)))
        }
    }

    private func rebuildAudioTracks(_ menu: NSMenu) {
        menu.removeAllItems()
        guard !menuState.audioTracks.isEmpty else {
            menu.addItem(disabled("No audio tracks"))
            return
        }
        for track in menuState.audioTracks {
            let item = menuItem(track.title, .selectAudioTrack(track.id))
            item.state = menuState.selectedAudioTrack == track.id ? .on : .off
            menu.addItem(item)
        }
    }

    private func rebuildSubtitleTracks(_ menu: NSMenu) {
        menu.removeAllItems()

        let off = menuItem("Off", .selectSubtitleTrack(nil))
        off.state = menuState.selectedSubtitleTrack == nil ? .on : .off
        menu.addItem(off)

        guard !menuState.subtitleTracks.isEmpty else { return }
        menu.addItem(.separator())
        for track in menuState.subtitleTracks {
            let title = track.title + (track.isForced ? " (forced)" : "")
            let item = menuItem(title, .selectSubtitleTrack(track.id))
            item.state = menuState.selectedSubtitleTrack == track.id ? .on : .off
            menu.addItem(item)
        }
    }

    /// A label, not a control. `action: nil` is what greys it out — AppKit disables
    /// any item with no action, so this needs no validation case of its own.
    private func disabled(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    // MARK: - Self-verification

    /// Drives the menus exactly as AppKit would on open and logs the result, under
    /// `LUMIERE_DUMP_MENUS=1`.
    ///
    /// Clicking a real menu needs Accessibility permission a build shell does not
    /// have, so without this there is no way to tell an enabled Playback menu from
    /// a disabled one — which is precisely the bug that shipped through three
    /// phases unnoticed. Asserting on the state the OS would compute is the only
    /// honest check available here.
    func dumpMenuState(_ menus: [NSMenu]) {
        Diagnostics.log("[menu] --- state dump (active=\(menuState.isActive)) ---")
        for menu in menus {
            menuNeedsUpdate(menu)
            var enabled = 0
            var lines: [String] = []
            for item in menu.items where !item.isSeparatorItem {
                if let submenu = item.submenu {
                    menuNeedsUpdate(submenu)
                    let live = submenu.items.filter { $0.action != nil && validateMenuItem($0) }
                    lines.append("  \(item.title)/ \(live.count) of \(submenu.items.count) enabled")
                    enabled += live.count
                    continue
                }
                guard item.action != nil else { continue }
                let ok = validateMenuItem(item)
                if ok { enabled += 1 }
                let tick = item.state == .on ? " ✓" : ""
                lines.append("  \(item.title): \(ok ? "enabled" : "disabled")\(tick)")
            }
            Diagnostics.log("[menu] \(menu.title) — \(enabled) enabled")
            for line in lines { Diagnostics.log("[menu] \(line)") }
        }
    }
}
