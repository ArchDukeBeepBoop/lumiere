import AppKit
import ControlCore
import SwiftUI

/// The Restore rows in the Library section. See `BackupRestorer`.
struct BackupRows: View {
    @Bindable var backups: BackupRestorer
    let server: ServerProcess

    @State private var isHovering = false

    var body: some View {
        Group {
            if let newest = backups.backups.first {
                // A pop-up of dates behind a row that looks like every other
                // row, with the chevron system menus use for "more inside".
                SwiftUI.Menu {
                    Section("Restore the library as it was on…") {
                        ForEach(backups.backups) { backup in
                            Button(backup.date.formatted(date: .complete, time: .shortened)) {
                                Task { await backups.restore(backup, server: server) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        IconCircle(symbol: "clock.arrow.circlepath")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Restore Backup").font(Menu.body)
                            Text("\(backups.backups.count) daily copies · newest "
                                 + newest.date.formatted(.relative(presentation: .named)))
                                .font(Menu.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: Menu.rowHeight + 6)
                    .background(Hover(isOn: isHovering))
                    .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .onHover { isHovering = $0 }
                .padding(.horizontal, Menu.gutter - 6)
            } else {
                MenuNote(text: "No backups yet — the server makes one each day.")
            }
            let old = OldCopies.list(in: BackupRestorer.dataDir)
            if !old.isEmpty {
                let total = ByteCountFormatter.string(
                    fromByteCount: old.reduce(0) { $0 + $1.bytes }, countStyle: .file)
                MenuRow(symbol: "trash", title: "Move Old Copies to Trash…",
                        detail: "\(old.count) · \(total)") {
                    confirmTrash(old, total: total)
                }
            }
            if let message = backups.message {
                MenuNote(text: message)
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
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let moved = OldCopies.trash(old)
        backups.note("Moved \(moved) old copies to the Trash.")
    }
}
