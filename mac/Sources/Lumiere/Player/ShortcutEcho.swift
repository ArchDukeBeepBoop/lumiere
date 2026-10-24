import AppKit
import LumiereKit

/// The key that caused an on-screen message, shown beside it — "Subtitles
/// +0.1 s  ⌥⌘]". VLC's redesign asked for exactly this: a message that names
/// the action but not the key leaves you unable to undo what you pressed.
///
/// Noted where key presses arrive — the player's key view and the menu bar —
/// and read by `PlayerOSD` if the message followed within a moment.
@MainActor
enum ShortcutEcho {
    private(set) static var last: (keys: String, at: Date)?

    static func note(_ event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat,
              Preference.osdShowsShortcut.value else { return }
        last = (describe(event), Date())
    }

    /// The keys for a message shown at `date`, if one was pressed just before.
    static func keys(for date: Date) -> String? {
        guard let last, abs(date.timeIntervalSince(last.at)) < 0.6 else { return nil }
        return last.keys
    }

    /// As the menu bar writes a shortcut: modifiers in Apple's order, then the key.
    static func describe(_ event: NSEvent) -> String {
        let flags = event.modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyName(event)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            return chars.uppercased()
        }
    }
}
