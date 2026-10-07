import SwiftUI
import LumiereKit

/// What the library is doing, and the one button that makes it current.
///
/// Rebuilt around what the server now is. It used to be a stack of settings
/// cards — last pass, server scan, depth, libraries, a note — because the sync
/// was a set of options you configured before pressing something. But the server
/// scans the disk itself now, so the honest shape is a *status*: one headline
/// number, the work as it happens, and a single action.
///
/// The Apple TV reading of that: large type carrying the thing you came to find
/// out, one primary action, and everything secondary set quietly beneath it
/// rather than boxed. The options that used to be cards are still here — which
/// libraries, how deep, what the last pass did — but as a strip at the bottom
/// rather than as the subject of the screen.
struct SyncPanel: View {
    @Bindable var app: AppModel
    let onDone: () -> Void

    /// Not private: SyncPanel+ServerScan.swift and +Options.swift drive these,
    /// and Swift's `private` is file-scoped.
    @State var isScanningServer = false
    @State var serverScanMessage: String?
    /// The server's own scan, polled while this panel is open. Nil until the
    /// first answer, which is what tells a Jellyfin server apart from ours.
    @State var scan: ServerScanStatus?
    @State var showsOptions = false

    var isSyncing: Bool { app.syncProgress != nil }
    var isScanning: Bool { scan?.Running == true }

    var scannable: [LibraryRecord] {
        app.libraries.filter { $0.serverId != LocalLibrary.serverId && $0.holdsPlayableVideo }
    }

    var canScan: Bool {
        !app.isOffline && !app.syncSelection.libraries(from: app.libraries).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            close
            headline
            Spacer(minLength: Theme.Space.lg)
            detail
            Spacer(minLength: Theme.Space.lg)
            action
            if showsOptions {
                Divider().padding(.vertical, Theme.Space.md)
                options
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 560, height: showsOptions ? 660 : 460)
        .background(Theme.Palette.canvas)
        .animation(Theme.Motion.transition, value: showsOptions)
        .animation(Theme.Motion.transition, value: isScanning)
        .task { await pollScan() }
    }

    private var close: some View {
        HStack {
            Spacer()
            Button("Close") { onDone() }
                .buttonStyle(.plain)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
        }
    }

    /// The one thing somebody opened this to find out, set large.
    ///
    /// Not a title and a subtitle: the title would say "Library Sync", which the
    /// reader already knows, and the state would be the small text under it.
    /// This inverts that — the state *is* the headline.
    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(headlineText)
                .font(Theme.Font.hero)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(headlineDetail)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Space.sm)
    }

    private var headlineText: String {
        if isScanning { return "Reading the disk" }
        if isSyncing { return "Bringing it across" }
        if app.isOffline { return "Server unreachable" }
        if let error = scan?.Error, !error.isEmpty { return "A library could not be read" }
        return "Library is up to date"
    }

    private var headlineDetail: String {
        if let error = scan?.Error, !error.isEmpty, !isScanning { return error }
        if isScanning, let scan {
            let library = scan.Library ?? "…"
            guard let index = scan.Index, let total = scan.Total else { return library }
            return "\(library) — library \(index) of \(total)"
        }
        if let progress = app.syncProgress {
            return "\(progress.libraryName) — library \(progress.libraryIndex) "
                 + "of \(progress.libraryCount)"
        }
        if app.feedIsLive {
            // The feed's whole promise, said once: nothing to press.
            let checked = app.lastSyncFinished.map {
                " Last change \(Self.relative.localizedString(for: $0, relativeTo: Date()))."
            } ?? ""
            return "New, changed and removed titles arrive as they happen." + checked
        }
        if let finished = app.lastSyncFinished {
            return "Last checked \(Self.relative.localizedString(for: finished, relativeTo: Date()))"
        }
        return "Nothing checked in this session yet"
    }

    /// The counts, as three numbers rather than a paragraph.
    ///
    /// A scan of 43,000 files is not legible as prose, and a percentage bar over
    /// nine libraries of wildly different sizes is a number that means nothing.
    /// Three counts that each mean one thing is the honest readout.
    @ViewBuilder
    private var detail: some View {
        if let scan, scan.Files > 0 || scan.Running {
            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                figure(scan.Files, "files on disk")
                figure(scan.Added, "added")
                figure(scan.Missing, "missing")
                if let unresolved = scan.UnresolvedLinks, unresolved > 0 {
                    // A release whose opening and ending live in files the
                    // library does not have. Said here because VLC's answer to
                    // the same case is silence.
                    figure(unresolved, "missing OP/ED")
                }
            }
        } else if let progress = app.syncProgress {
            SyncActiveCard(app: app, progress: progress)
        } else if let summary = app.lastSyncSummary {
            Text(Self.describe(summary))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(Theme.Font.shelfTitle)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
        }
    }

    /// One primary action, and the rest kept quiet beside it.
    private var action: some View {
        HStack(spacing: Theme.Space.md) {
            Button(actionTitle) { Task { await scanServer() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canScan || isScanning || isScanningServer)

            if isSyncing {
                Button("Stop") { app.cancelSync() }
            }

            Spacer()

            Button(showsOptions ? "Hide Options" : "Options") {
                showsOptions.toggle()
            }
            .buttonStyle(.plain)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.accent)
        }
    }

    private var actionTitle: String {
        if isScanning { return "Scanning…" }
        if isSyncing { return "Syncing…" }
        return "Check for New"
    }

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// What the last pass did, in counts rather than adjectives.
    ///
    /// "Removed 7 titles" is the only evidence the owner has that a pass noticed
    /// the files they deleted, so it is stated plainly.
    static func describe(_ summary: AppModel.SyncSummary) -> String {
        let kind = summary.wasFullScan ? "Full scan" : "Quick pass"
        let libraries = summary.libraries == 1 ? "1 library" : "\(summary.libraries) libraries"
        let seen = "\(summary.seen.formatted()) items read"
        let removed = summary.removed == 0
            ? "nothing removed"
            : (summary.removed == 1
               ? "1 title removed"
               : "\(summary.removed.formatted()) titles removed")
        return "\(kind) · \(libraries) · \(seen) · \(removed)"
    }
}
