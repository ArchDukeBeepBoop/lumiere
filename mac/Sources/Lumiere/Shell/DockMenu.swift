import AppKit
import LumiereKit

/// Continue Watching on the Dock icon's menu, as Music and TV keep their
/// recent items there: right-click Lumiere in the Dock, pick up where you were.
///
/// Rebuilt from the same query as the home row, so it honours the private
/// room — and is emptied while the room is open, because the Dock is on
/// screen for everyone.
@MainActor
enum DockMenu {
    private static var entries: [(id: String, title: String)] = []

    static func refresh(_ app: AppModel) async {
        guard !app.isShowingPrivateLibraries, let repository = app.repository else {
            entries = []
            return
        }
        let resume = (try? await repository.resumeEntries(limit: 6)) ?? []
        entries = resume.map { entry in
            let item = entry.item
            let title = item.seriesName.map { "\($0) — \(item.name)" } ?? item.name
            return (item.id, title)
        }
    }

    static func menu() -> NSMenu {
        let menu = NSMenu()
        guard !entries.isEmpty else { return menu }
        let header = NSMenuItem(title: "Continue Watching", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(DockTarget.open(_:)), keyEquivalent: "")
            item.target = DockTarget.shared
            item.representedObject = entry.id
            item.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
            menu.addItem(item)
        }
        return menu
    }
}

/// The menu items' target. NSMenu does not retain targets, so it lives forever.
@MainActor
final class DockTarget: NSObject {
    static let shared = DockTarget()

    @objc func open(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openDetail, object: id)
    }
}
