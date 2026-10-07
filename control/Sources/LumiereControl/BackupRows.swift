import AppKit
import ControlCore
import SwiftUI

/// The Restore rows in the Library section. See `BackupRestorer`.
struct BackupRows: View {
    @Bindable var backups: BackupRestorer
    let server: ServerProcess

    var body: some View {
        Group {
            if let newest = backups.backups.first {
                SwiftUI.Menu {
                    ForEach(backups.backups) { backup in
                        Button(backup.date.formatted(date: .abbreviated, time: .shortened)) {
                            Task { await backups.restore(backup, server: server) }
                        }
                    }
                } label: {
                    Label("Restore Backup…", systemImage: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, Menu.gutter)
                .padding(.vertical, 4)
                MenuNote(symbol: nil, text: "\(backups.backups.count) daily copies; newest "
                         + newest.date.formatted(date: .abbreviated, time: .shortened) + ".")
            } else {
                MenuNote(symbol: nil, text: "No backups yet — the server takes one a day.")
            }
            let old = OldCopies.list(in: BackupRestorer.dataDir)
            if !old.isEmpty {
                let total = ByteCountFormatter.string(
                    fromByteCount: old.reduce(0) { $0 + $1.bytes }, countStyle: .file)
                MenuRow(symbol: "trash", title: "Move Old Copies to Trash…",
                        detail: "\(old.count), \(total)") {
                    confirmTrash(old, total: total)
                }
            }
            if let message = backups.message {
                MenuNote(symbol: nil, text: message)
            }
        }
        .onAppear { backups.refresh() }
    }

    /// Asks, then moves the hand-made copies to the Trash — from where they
    /// can still be put back. The daily backups are not touched.
    private func confirmTrash(_ old: [OldCopies.Copy], total: String) {
        let alert = NSAlert()
        alert.messageText = "Move \(old.count) old database copies (\(total)) to the Trash?"
        alert.informativeText = old.map(\.url.lastPathComponent).joined(separator: "\n")
            + "\n\nThese were made by hand before changes. The live library and the "
            + "daily backups are not touched, and the Trash can give these back."
        MenuLook.style(alert)
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let moved = OldCopies.trash(old)
        backups.note("Moved \(moved) old copies to the Trash.")
    }
}
