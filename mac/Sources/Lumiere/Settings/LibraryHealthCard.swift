import SwiftUI
import AppKit
import LumiereKit

/// What is wrong with the library, counted, with the passes that fix it.
///
/// Every cleanup so far — hollow shows, blank tiles, episodes named after
/// their files, a download that was all zeros — was found by stumbling on it
/// one tile at a time. This shows each kind at once, with a few examples, and
/// the two server passes that mend most of them one click away.
struct LibraryHealthCard: View {
    let app: AppModel

    @State var issues: [LibraryHealthIssue]?
    @State var expanded: Set<String> = []
    @State var status: String?
    @State var isWorking = false
    /// The duplicate film waiting for the Move to Trash confirmation.
    @State var trashing: LibraryHealthIssue.Sample?
    /// A show opened in Identify from "Shows matched to the wrong entry".
    @State var identifying: LibraryEntry?

    var body: some View {
        SettingsCard(
            title: "Library Health",
            icon: "stethoscope",
            subtitle: "Shows with nothing in them, blank tiles, unnamed episodes"
        ) {
            if let issues {
                ForEach(issues) { issue in row(issue) }
            } else {
                Text("Checking…").font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }

            HStack {
                Button("Scan and Repair") { Task { await run(scan: true) } }
                Button("Name and Credit") { Task { await run(scan: false) } }
                if (issues?.first { $0.kind == "MissingArtwork" }?.count ?? 0) > 0 {
                    Button("Take Frames Now") { Task { await takeFrames() } }
                }
                Button("Check Again") { Task { await load() } }
                Button("Show Ignored") {
                    Task {
                        try? await app.client?.restoreHealth()
                        await load()
                    }
                }
            }
            .font(Theme.Font.caption)
            .disabled(isWorking)

            caption("Scan and Repair re-reads the folders: it folds duplicate "
                  + "shows, drops empty ones and takes frames for tiles with no "
                  + "picture. Name and Credit asks TMDB for titles and cast. "
                  + "An unreadable file has to be replaced by hand.")
            if let status { caption(status) }
        }
        .task { await load() }
        .homeIdentifySheet(entry: $identifying, app: app) { await load() }
        .confirmationDialog(
            "Move \(trashing?.name ?? "this file") to the Trash?",
            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })
        ) {
            Button("Move to Trash", role: .destructive) {
                guard let sample = trashing else { return }
                Task {
                    do {
                        try await app.repository?.deleteToTrash(itemId: sample.id)
                        app.reportTrashed(sample.name)
                        await load()
                    } catch {
                        status = "Not moved: \(error.localizedDescription)"
                    }
                }
            }
        } message: {
            Text(trashing.map { "\($0.path)\n\(Self.size(of: $0.path)) — the other copy stays." } ?? "")
        }
    }

    /// A file's size for the duplicate rows, or "missing".
    static func size(of path: String) -> String {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
        else { return "missing" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder
    private func row(_ issue: LibraryHealthIssue) -> some View {
        let open = expanded.contains(issue.kind)
        Button {
            if open { expanded.remove(issue.kind) } else { expanded.insert(issue.kind) }
        } label: {
            HStack {
                Image(systemName: issue.count == 0 ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(issue.count == 0 ? Theme.Palette.textMuted : Theme.Palette.accent)
                Text(Self.title(issue.kind))
                if let change = issue.changeSinceYesterday {
                    Text(change).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                }
                Spacer()
                Text(issue.count.formatted()).monospacedDigit()
                if issue.count > 0 {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(issue.count == 0)

        if open {
            if issue.kind == "MisfiledEpisodes", issue.samples.count > 1 {
                Button("Move All \(issue.samples.count) to Their Seasons") {
                    Task { await moveAllMisfiled(issue.samples) }
                }
                .font(Theme.Font.caption)
                .padding(.leading, Theme.Space.lg)
            }
            issueActions(issue)
            ForEach(issue.samples) { sample in
                HStack {
                    Text(sample.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    // A broken file keeps turning up on Continue Watching and
                        // Next Up until it is replaced. Hiding it there is the
                        // existing hidden list — reversible in Settings.
                    // Merge, for a collection that repeats another. See +Fixes.
                    sampleActions(issue, sample)
                    // A show's gaps may be deliberate — skipped filler, a
                    // recap nobody wants. Ignored, it stops counting.
                    if issue.kind == "MissingEpisodes" {
                        Button("Ignore") {
                            Task {
                                try? await app.client?.dismissHealth(kind: issue.kind, key: sample.id)
                                await load()
                            }
                        }
                    }
                    // The order the naming pass found fits this show's folders:
                    // applied as Episode Order… would, which renames the show.
                    if issue.kind == "OrderSuggestions" {
                        Button("Use This Order") {
                            Task {
                                try? await app.repository?.setEpisodeGroup(seriesId: sample.id, groupId: sample.path)
                                status = "Renaming \(sample.name.components(separatedBy: " — ").first ?? "the show") in that order."
                                await load()
                            }
                        }
                        Button("Ignore") {
                            Task {
                                try? await app.client?.dismissHealth(kind: issue.kind, key: sample.id)
                                await load()
                            }
                        }
                    }
                    if issue.kind == "MisfiledEpisodes" {
                        Button("Move to Its Season") { Task { await moveMisfiled(sample) } }
                    }
                    if issue.kind == "Unreadable" {
                        Button("Hide from Shelves") {
                            Task {
                                try? await app.repository?.hideFromShelves(itemId: sample.id)
                                status = "\(sample.name) is hidden from shelves until you unhide it."
                            }
                        }
                    }
                    if !sample.path.isEmpty, issue.kind != "OrderSuggestions" {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: sample.path)])
                        }
                    }
                }
                .font(Theme.Font.caption)
                .padding(.leading, Theme.Space.lg)
                // A show's seasons, each ignorable alone: skipping one filler
                // arc should not hide the rest of the show's gaps.
                if issue.kind == "MissingEpisodes", let parts = sample.parts, parts.count > 1 {
                    ForEach(parts) { part in
                        HStack {
                            Text(part.name).lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Button("Ignore Season") {
                                Task {
                                    try? await app.client?.dismissHealth(
                                        kind: "MissingEpisodesSeason", key: part.id)
                                    await load()
                                }
                            }
                        }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .padding(.leading, Theme.Space.xl + Theme.Space.md)
                    }
                }
                copyRows(issue, sample)
            }
            if issue.count > issue.samples.count {
                caption("and \(issue.count - issue.samples.count) more")
                    .padding(.leading, Theme.Space.lg)
            }
        }
    }

    static func title(_ kind: String) -> String {
        switch kind {
        case "EmptySeries": return "Shows with no episodes"
        case "MissingArtwork": return "Files with no picture"
        case "Unreadable": return "Files that could not be read"
        case "UnnamedEpisodes": return "Episodes named after their file"
        case "MissingEpisodes": return "Episodes missing from a season"
        case "DuplicateFilms": return "Films in more than one file"
        case "LibraryShrank": return "Library shrank overnight"
        case "MisfiledEpisodes": return "Episodes in the wrong season folder"
        case "BackupUnusable": return "Newest backup can't be restored"
        case "OrderSuggestions": return "Shows that fit another episode order"
        case "UnlistedEpisodes": return "Episodes no page would list"
        case "UnplacedFiles": return "Files in a TV library under no show"
        case "EmptyCollections": return "Collections with nothing in them"
        case "DuplicateCollections": return "Collections that repeat another"
        case "CollectionsWithGoneTitles": return "Collections holding titles that are gone"
        case "MismatchedShows": return "Shows matched to the wrong entry"
        case "UnplacedExtras": return "Extras no title can claim"
        default: return kind
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    func load() async {
        // The demo library has no server; its report is a fixture, so the
        // walkthrough can show every fix. See `LibraryHealthIssue.demo`.
        if app.isDemo { issues = LibraryHealthIssue.demo; return }
        do {
            issues = try await app.client?.libraryHealth()
            if let issues { LibraryHealthWatch.shared.acknowledge(issues) }
        } catch {
            issues = []
            status = "This server does not report library health."
        }
    }

}
