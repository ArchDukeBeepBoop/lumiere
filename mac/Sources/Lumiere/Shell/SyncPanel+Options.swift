import SwiftUI
import LumiereKit

/// The two choices the sync panel now offers: how deep, and which libraries.
///
/// Split from SyncPanel.swift for the project's 300-line limit. Both write through
/// `AppModel.updateSyncSelection`, which is the only thing that persists the
/// selection — a binding that wrote the property directly would look identical on
/// screen and be forgotten on the next launch.
extension SyncPanel {

    /// Quick versus full, described by what each one can and cannot notice.
    ///
    /// The wording is the point. "Incremental" and "full" are the code's words; the
    /// owner's question was why deleted files were still listed, and the answer —
    /// only the full pass looks at the whole library, so only the full pass can tell
    /// that something is missing — belongs on screen rather than in a commit message.
    @ViewBuilder
    var depthCard: some View {
        // With the change feed there is no depth to choose: removals and
        // edits arrive as they happen, like additions.
        if !app.feedIsLive {
        SettingsCard(title: "Scan Depth", icon: "slider.horizontal.3") {
            Picker("", selection: depthBinding) {
                Text("Quick — find new items").tag(SyncSelection.Depth.quick)
                Text("Full — also notice removed items").tag(SyncSelection.Depth.full)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            SettingsNote(app.syncSelection.depth == .quick
                ? "Reads newest-first and stops as soon as a whole page is already "
                + "known, so it usually costs a request or two rather than a walk of "
                + "the whole library. It finds new episodes and new titles quickly, "
                + "but it never sees the rest of the library — so it cannot remove a "
                + "title whose file you deleted, moved or renamed. Only a full scan can."
                : "Reads every item in each ticked library and then removes anything "
                + "the server no longer has. This is the only pass that clears out "
                + "titles whose files were deleted, moved or renamed on disk. It takes "
                + "minutes on a large library, and it is safe to stop — a pass that "
                + "does not finish reading never removes anything.")
        }
        }
    }

    private var depthBinding: Binding<SyncSelection.Depth> {
        Binding(
            get: { app.syncSelection.depth },
            set: { depth in app.updateSyncSelection { $0.depth = depth } }
        )
    }

    /// One checkbox per library, remembered between launches.
    var librariesCard: some View {
        SettingsCard(
            title: "Libraries",
            icon: "square.stack",
            subtitle: selectionSummary,
            accessory: { selectAllButton },
            content: {
                if scannable.isEmpty {
                    SettingsNote("No video libraries yet. They appear here once the "
                               + "server has been read at least once.")
                } else {
                    ForEach(scannable) { library in
                        libraryRow(library)
                    }
                    SettingsNote("Unticked libraries are skipped by every sync, "
                               + "including the automatic one at launch. Their cached "
                               + "titles stay browsable — nothing is deleted by "
                               + "unticking a library.")
                }
            }
        )
    }

    private func libraryRow(_ library: LibraryRecord) -> some View {
        Toggle(isOn: Binding(
            get: { app.syncSelection.includes(library.id) },
            set: { on in app.updateSyncSelection { $0.setIncluded(on, for: library.id) } }
        )) {
            HStack(spacing: Theme.Space.sm) {
                Text(library.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                // Carried over from the old panel: a library that missed a page last
                // time is the one you most want to re-tick and run again.
                if app.lastPartialLibraries.contains(library.name) {
                    Label("incomplete last time", systemImage: "exclamationmark.circle")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.danger)
                }
                Spacer(minLength: 0)
            }
        }
        .toggleStyle(.checkbox)
        // Changing what a running pass reads mid-pass would make the progress
        // readout lie about what it is doing, and the loop has already resolved
        // its list. The choice applies to the next scan.
        .disabled(isSyncing)
    }

    private var selectionSummary: String {
        let selected = app.syncSelection.libraries(from: app.libraries).count
        guard !scannable.isEmpty else { return "None found" }
        if selected == scannable.count { return "All \(scannable.count) will be scanned" }
        if selected == 0 { return "None ticked — nothing would be scanned" }
        return "\(selected) of \(scannable.count) will be scanned"
    }

    /// All / None, and the reason both values are read *before* the closure runs.
    ///
    /// This crashed the app. `updateSyncSelection` takes its argument `inout`, so
    /// for as long as the closure is running Swift holds an exclusive access on
    /// `app.syncSelection` — and `allSelected` reads `app.syncSelection`. Evaluating
    /// it inside the closure is a second, overlapping access to memory already
    /// being written, which is a hard trap at runtime rather than a warning: the
    /// process dies the moment the button is pressed. Reading it once, up here,
    /// is also the correct semantics — "all of them are ticked" is a question about
    /// the state before the change, not a value that should shift underneath a loop.
    private var selectAllButton: some View {
        let isTicking = !allSelected
        let ids = scannable.map(\.id)
        return Button(isTicking ? "All" : "None") {
            app.updateSyncSelection { selection in
                for id in ids { selection.setIncluded(isTicking, for: id) }
            }
        }
        .font(Theme.Font.caption)
        .disabled(isSyncing || scannable.isEmpty)
    }

    private var allSelected: Bool {
        !scannable.isEmpty && scannable.allSatisfy { app.syncSelection.includes($0.id) }
    }
}
