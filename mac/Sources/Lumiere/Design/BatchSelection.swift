import SwiftUI
import LumiereKit

/// Selecting many things at once, and acting on all of them.
///
/// Every action in this app is a right-click on one poster, which is right until
/// the answer is "these forty". Starring a season of favourites, adding a franchise
/// to a collection, or marking a run watched is forty menus otherwise, and nobody
/// does it twice.
///
/// Held as an observable rather than a `@State` set so a toolbar, a grid and a
/// footer can all read the same selection without threading bindings through every
/// layer between them.
@MainActor
@Observable
final class BatchSelection {
    /// Off until asked for. A grid where a click selects rather than opens is a
    /// different grid, and it should never be the one you land on.
    private(set) var isActive = false
    private(set) var ids: Set<String> = []

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    /// What the last batch actually did, shown in the bar.
    ///
    /// Every one of these calls the server once per item, and both of the
    /// underlying writes report success — which the batch paths were throwing
    /// away. Twenty-five failures out of forty looked exactly like forty
    /// successes, which on a favourite is annoying and on a watched-state change
    /// is a lie about what you have seen.
    private(set) var outcome: String?

    /// Runs `work` over the selection, counting what failed and stopping early if
    /// the selection is dismissed mid-flight.
    ///
    /// Sequential rather than concurrent on purpose: forty parallel writes against
    /// a Mac mini serving video is how a sync starts timing out, and the whole
    /// point of the earlier sync work was to stop hammering it.
    func run(_ work: (String) async -> Bool) async {
        let targets = Array(ids)
        var failed = 0
        var done = 0
        for id in targets {
            // Done, or Escape, stops the run rather than finishing silently in
            // the background against items you can no longer see.
            guard isActive else { break }
            if await work(id) == false { failed += 1 }
            done += 1
        }

        outcome = switch (failed, done < targets.count) {
        case (0, false): nil
        case (0, true): "Stopped after \(done) of \(targets.count)."
        case (let count, _):
            "\(count) of \(done) didn't apply — the server refused or was unreachable."
        }
    }

    func clearOutcome() { outcome = nil }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    func begin(with id: String? = nil) {
        isActive = true
        outcome = nil
        if let id { ids.insert(id) }
    }

    func end() {
        isActive = false
        ids = []
        outcome = nil
    }

    func selectAll(_ all: [String]) { ids = Set(all) }

    func clear() { ids = [] }
}

/// The tick that marks a selected tile.
///
/// Drawn over the artwork rather than beside it, because the artwork is what you
/// are aiming at — a checkbox in a margin means hitting a five-point target to
/// choose a two-hundred-point poster.
struct SelectionOverlay: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.poster)
                    .strokeBorder(Theme.Palette.accent, lineWidth: 3)
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    isSelected ? Theme.Palette.onAccent : Theme.Palette.onArtwork,
                    isSelected ? Theme.Palette.accent : Theme.Palette.onArtwork.opacity(0.5)
                )
                .padding(Theme.Space.sm)
                // A tick that only appears once something is selected gives no hint
                // that a tile is selectable at all, so the empty circle stays.
                .shadow(radius: 2)
        }
        .allowsHitTesting(false)
    }
}

/// The bar that appears while a selection is live: what is chosen, and what can be
/// done with it.
///
/// Pinned to the bottom rather than replacing the toolbar, so the filter and sort
/// you used to *find* these forty things stay where they were.
struct BatchActionBar: View {
    let selection: BatchSelection
    let totalVisible: Int
    var onSelectAll: () -> Void
    var onFavourite: (() async -> Void)?
    var onMarkWatched: ((Bool) async -> Void)?
    var onAddToCollection: (() -> Void)?
    var onAddToPlaylist: (() -> Void)?
    /// Queues subtitles for every selected show. Nil where the selection
    /// cannot hold shows.
    var onQueueSubtitles: (() async -> Void)? = nil

    @State private var isWorking = false

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(selection.isEmpty
                     ? "Select items"
                     : "\(selection.count) selected")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                // Said here rather than in a dialog: a batch that half-worked is
                // information, not an interruption.
                if let outcome = selection.outcome {
                    Text(outcome)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.danger)
                        .lineLimit(1)
                }
            }

            // Says what it will actually select. It only ever covered the loaded
            // page — up to 60 rows of 24,000 — while the toolbar above read the
            // library total, so "Select All" then "Mark Unwatched" looked like it
            // was about to wipe resume positions across the whole library.
            Button(selection.count == totalVisible
                   ? "Select None" : "Select All \(totalVisible) Loaded") {
                if selection.count == totalVisible { selection.clear() } else { onSelectAll() }
            }
            .font(Theme.Font.caption)

            Spacer()

            if !selection.isEmpty {
                if let onFavourite {
                    action("Favourite", icon: "star") { await onFavourite() }
                }
                if let onMarkWatched {
                    action("Mark Watched", icon: "eye") { await onMarkWatched(true) }
                    action("Mark Unwatched", icon: "eye.slash") { await onMarkWatched(false) }
                }
                if let onAddToCollection {
                    Button("Add to Collection…", action: onAddToCollection)
                        .font(Theme.Font.caption)
                }
                if let onAddToPlaylist {
                    Button("Add to Playlist…", action: onAddToPlaylist)
                        .font(Theme.Font.caption)
                }
                if let onQueueSubtitles {
                    action("Queue Subtitles", icon: "captions.bubble") { await onQueueSubtitles() }
                }
            }

            Button("Done") { selection.end() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.vertical, Theme.Space.md)
        .liquidGlass(Rectangle())
        .overlay(alignment: .top) { Divider() }
    }

    private func action(
        _ title: String, icon: String, work: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                isWorking = true
                await work()
                isWorking = false
            }
        } label: {
            Label(title, systemImage: icon).font(Theme.Font.caption)
        }
        .disabled(isWorking)
    }
}
