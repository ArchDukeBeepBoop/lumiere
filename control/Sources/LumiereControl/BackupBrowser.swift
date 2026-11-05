import AppKit
import ControlCore
import SwiftUI

/// Every backup, side by side, before choosing one to go back to.
///
/// The menu's list is dates only, and a date is not what anyone remembers.
/// What they remember is "it had everything" or "I had watched that". So each
/// copy is opened read-only and counted: how big the library was, how much of
/// it had been watched, what was half-way through — the way Time Machine shows
/// you the folder as it was, rather than a timestamp.
struct BackupBrowser: View {
    static let windowID = "backups"
    @Bindable var backups: BackupRestorer
    let server: ServerProcess
    @State private var counts: [URL: LibraryStats] = [:]
    @State private var selection: BackupRestorer.Backup.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backups").font(.title2.weight(.semibold))
                    Text(backups.health.text)
                        .foregroundStyle(backups.health.warning ? .red : .secondary)
                }
                Spacer()
                Button("Restore…") { restoreSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            Table(backups.backups, selection: $selection) {
                TableColumn("Date") { b in
                    Text(b.date.formatted(date: .abbreviated, time: .shortened))
                }
                .width(min: 150)
                TableColumn("Where") { b in
                    Label(b.onMirror ? "Second disk" : "This Mac",
                          systemImage: b.onMirror ? "externaldrive" : "laptopcomputer")
                }
                TableColumn("Library") { b in figure(b) { "\($0.films) films · \($0.shows) shows" } }
                    .width(min: 150)
                TableColumn("Watched") { b in figure(b) { "\($0.watched)" } }
                    .width(70)
                TableColumn("In progress") { b in figure(b) { "\($0.inProgress)" } }
                    .width(80)
            }
            .contextMenu(forSelectionType: BackupRestorer.Backup.ID.self) { _ in
                Button("Restore…") { restoreSelected() }
                Button("Show in Finder") {
                    if let url = selection { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            } primaryAction: { _ in restoreSelected() }
            Text("Each copy is the whole library as it was that night. Restoring sets "
                 + "today's aside beside it — nothing is deleted. Private libraries are left out of the counts.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 380)
        .onAppear {
            backups.refresh()
            NSApp.activate(ignoringOtherApps: true)
        }
        .task(id: backups.backups.map(\.id)) { await count() }
    }

    @ViewBuilder
    private func figure(_ b: BackupRestorer.Backup, _ text: (LibraryStats) -> String) -> some View {
        if let stats = counts[b.url] {
            Text(text(stats)).monospacedDigit()
        } else {
            ProgressView().controlSize(.small)
        }
    }

    /// One copy at a time, off the main thread, newest first — the ones a
    /// person is most likely to want are the first to fill in.
    private func count() async {
        for backup in backups.backups where counts[backup.url] == nil {
            let url = backup.url
            let stats = await Task.detached(priority: .utility) {
                LibraryStats.read(database: url)
            }.value
            if let stats { counts[url] = stats }
        }
    }

    private func restoreSelected() {
        guard let id = selection, let backup = backups.backups.first(where: { $0.id == id }) else { return }
        Task { await backups.restore(backup, server: server) }
    }
}
