import SwiftUI
import LumiereKit

/// Albums and artists as a wall of square, rounded tiles that open in place.
///
/// Square because album art is square — a 2:3 poster frame would letterbox every
/// cover in the library. And a grid rather than the list music started as: covers
/// are how anyone recognises an album, where a column of text is something you have
/// to read.
///
/// Expanding in place rather than pushing a screen: opening an album to see six
/// tracks and then going back for the next one is a lot of navigation for a small
/// answer. The tracks appear directly under the row the tile sits in, so the rest of
/// the wall keeps its position.
struct MusicTileGrid<Menu: View>: View {
    let entries: [LibraryEntry]
    let pipeline: ImagePipeline
    let serverURL: URL
    /// Fetches the children of a tile the first time it is opened.
    let loadChildren: (LibraryEntry) async -> [LibraryEntry]
    let onPlayAudio: ([LibraryEntry], Int) -> Void
    /// Non-audio children — an artist's albums — drill in rather than play.
    let onOpen: (LibraryEntry) -> Void
    /// Called as the last rows come into view, so the browser can fetch the next
    /// page. Nil where the whole set is already in hand.
    var onReachedEnd: ((LibraryEntry) async -> Void)?
    /// Drawn above the first row, inside the same scroll view.
    ///
    /// Inside rather than above the grid so it scrolls away with the covers, which
    /// is what an artist header does everywhere else. A header stapled over a
    /// scrolling wall stays put and eats the top of the screen for the whole page.
    var header: AnyView?
    /// The right-click menu, supplied by the browser that owns the sheets and the
    /// favourite state. Nothing here knows what is on it.
    @ViewBuilder var menu: (LibraryEntry) -> Menu

    @State private var expanded: String?
    @State private var children: [String: [LibraryEntry]] = [:]
    @State private var loading: String?
    @Environment(\.displayScale) private var scale

    /// The smallest a cover may be drawn. The actual width is worked out per row
    /// so the wall fills its column — see `body`.
    private let minimumTile: CGFloat = 150

    var body: some View {
        // Rows are laid out by hand rather than with LazyVGrid, and that is the whole
        // fix for "the album doesn't collapse": a grid gives no way to insert anything
        // *between* its rows, so the track list could only be appended after the
        // entire wall. On a library of any size that put it hundreds of points below
        // the fold — the click worked, there was simply nothing to see. Chunking into
        // rows lets the tracks open directly beneath the tile that was clicked.
        GeometryReader { geometry in
            // Tiles stretch to fill the row rather than leaving the remainder at
            // the trailing edge. Fitting a whole number of 150pt tiles and letting
            // a Spacer eat what is left over put a gap of up to a full tile down
            // the right of every wall — enough to read as a column reserved for
            // something, which is exactly what it was not.
            let available = geometry.size.width - Theme.Space.xl * 2
            let columns = max(1, Int((available + Theme.Space.lg)
                                     / (minimumTile + Theme.Space.lg)))
            let tile = max(
                minimumTile,
                (available - Theme.Space.lg * CGFloat(columns - 1)) / CGFloat(columns)
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                    if let header { header }
                    ForEach(Array(rowsOf(columns: columns).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: Theme.Space.lg) {
                            ForEach(row) { entry in
                                tileCell(entry, width: tile)
                                    .task {
                                        if let onReachedEnd { await onReachedEnd(entry) }
                                    }
                            }
                            // A short final row still aligns left, so the last
                            // three albums do not spread across the window.
                            if row.count < columns {
                                Spacer(minLength: 0)
                            }
                        }

                        if let expanded, row.contains(where: { $0.id == expanded }) {
                            if let rows = children[expanded] {
                                trackList(rows)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Space.lg)
                            }
                        }
                    }
                }
                .padding(Theme.Space.xl)
            }
        }
    }

    private func rowsOf(columns: Int) -> [[LibraryEntry]] {
        stride(from: 0, to: entries.count, by: columns).map { start in
            Array(entries[start..<min(start + columns, entries.count)])
        }
    }

    private func tileCell(_ entry: LibraryEntry, width tile: CGFloat) -> some View {
        Button { toggle(entry) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                RemoteImage(
                    request: .poster(for: entry, serverURL: serverURL, width: tile, scale: scale),
                    pipeline: pipeline
                )
                .frame(width: tile, height: tile)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(
                            expanded == entry.id ? Theme.Palette.accent : Theme.Palette.border,
                            lineWidth: expanded == entry.id ? 2 : 1
                        )
                }
                .overlay(alignment: .center) {
                    if loading == entry.id {
                        ProgressView().controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.item.name)
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    if let artist = entry.item.seriesName ?? entry.item.overview {
                        Text(artist)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(width: tile, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menu(entry) }
    }

    /// The opened tile's contents, laid across the full width under the grid.
    @ViewBuilder
    private func trackList(_ rows: [LibraryEntry]) -> some View {
        if rows.isEmpty {
            // Said plainly rather than collapsing back to nothing, which reads as a
            // click that did not register.
            Text("No tracks on this one — the album is catalogued but its "
               + "files have not been scanned.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.lg)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        } else {
            populatedTrackList(rows)
        }
    }

    private func populatedTrackList(_ rows: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let tracks = rows.filter { $0.item.itemType == .audio }

            if !tracks.isEmpty {
                HStack {
                    Text("\(tracks.count) tracks")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                    Spacer()
                    Button("Play All") { onPlayAudio(tracks, 0) }
                        .font(Theme.Font.caption)
                }
                .padding(.bottom, Theme.Space.sm)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                Button {
                    if entry.item.itemType == .audio {
                        let tracks = rows.filter { $0.item.itemType == .audio }
                        onPlayAudio(tracks, tracks.firstIndex { $0.id == entry.id } ?? 0)
                    } else {
                        onOpen(entry)
                    }
                } label: {
                    HStack(spacing: Theme.Space.md) {
                        Text("\(index + 1)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .frame(width: 24, alignment: .trailing)
                        Text(entry.item.name)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let seconds = entry.item.runtimeSeconds, seconds > 0 {
                            Text(String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textMuted)
                        }
                        Image(systemName: entry.item.itemType == .audio ? "play.circle" : "chevron.right")
                            .font(.system(size: entry.item.itemType == .audio ? 14 : 11))
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                    .padding(.vertical, Theme.Space.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { menu(entry) }
                Divider()
            }
        }
        .padding(Theme.Space.lg)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func toggle(_ entry: LibraryEntry) {
        if expanded == entry.id {
            expanded = nil
            return
        }
        expanded = entry.id
        guard children[entry.id] == nil else { return }

        loading = entry.id
        Task {
            let rows = await loadChildren(entry)
            children[entry.id] = rows
            loading = nil
        }
    }
}
