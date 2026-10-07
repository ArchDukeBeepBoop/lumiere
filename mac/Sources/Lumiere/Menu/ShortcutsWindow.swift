import AppKit
import SwiftUI

/// Help › Keyboard Shortcuts: every shortcut the menu bar has, read from the
/// menu bar itself when the window opens — so the list cannot drift from the
/// menus the way a hand-written one would — plus the player's own bare keys,
/// which are not menu items and so have to be stated.
enum ShortcutsWindow {
    @MainActor private static var window: NSWindow?

    @MainActor
    static func show() {
        let rows = menuShortcuts() + playerKeys
        let host = NSHostingController(rootView: ShortcutsList(rows: rows))
        let window = Self.window ?? NSWindow(contentViewController: host)
        window.contentViewController = host
        window.title = "Keyboard Shortcuts"
        window.setContentSize(NSSize(width: 520, height: 640))
        window.isReleasedWhenClosed = false
        Self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    struct Row: Identifiable {
        let id = UUID()
        let menu: String
        let title: String
        let keys: String
    }

    @MainActor
    private static func menuShortcuts() -> [Row] {
        var rows: [Row] = []
        func walk(_ menu: NSMenu, _ top: String) {
            for item in menu.items {
                if let sub = item.submenu {
                    walk(sub, top.isEmpty ? item.title : top)
                } else if !item.keyEquivalent.isEmpty, !item.title.isEmpty {
                    rows.append(Row(menu: top, title: item.title, keys: keys(item)))
                }
            }
        }
        if let main = NSApp.mainMenu { walk(main, "") }
        return rows
    }

    private static func keys(_ item: NSMenuItem) -> String {
        let m = item.keyEquivalentModifierMask
        var out = ""
        if m.contains(.control) { out += "⌃" }
        if m.contains(.option) { out += "⌥" }
        if m.contains(.shift) || item.keyEquivalent != item.keyEquivalent.lowercased() { out += "⇧" }
        if m.contains(.command) { out += "⌘" }
        let key: String
        switch item.keyEquivalent.unicodeScalars.first.map({ Int($0.value) }) {
        case NSLeftArrowFunctionKey: key = "←"
        case NSRightArrowFunctionKey: key = "→"
        case NSUpArrowFunctionKey: key = "↑"
        case NSDownArrowFunctionKey: key = "↓"
        default: key = item.keyEquivalent.uppercased()
        }
        return out + key
    }

    private static let playerKeys: [Row] = [
        ("Space or K", "Play / Pause"), ("← / →  or  J / L", "Skip back / forward"),
        ("⇧← / ⇧→", "Long skip"), ("⌥← / ⌥→", "Previous / next chapter or marker"),
        ("Hold ← / →", "Scan; lands where you let go"), ("0 – 9", "Jump to 0–90%"), ("I", "Info, audio and subtitles"), ("P", "Picture in Picture"),
        ("↑ / ↓", "Volume"), ("M", "Mute"), ("F", "Full screen"),
        (", / .", "Paused: step a frame · Playing: slower / faster"),
        ("Z / ⇧Z", "Subtitles earlier / later"), ("Home / End", "Start / end"), ("Esc", "Close the player"),
    ].map { Row(menu: "In the player", title: $0.1, keys: $0.0) }
}

private struct ShortcutsList: View {
    let rows: [ShortcutsWindow.Row]

    var body: some View {
        List {
            ForEach(Array(Dictionary(grouping: rows, by: \.menu).keys.sorted()), id: \.self) { menu in
                Section(menu) {
                    ForEach(rows.filter { $0.menu == menu }) { row in
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text(row.keys).monospaced().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
