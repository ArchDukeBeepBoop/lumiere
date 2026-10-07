import SwiftUI
import LumiereKit

/// The track list, in columns.
///
/// A song is not one string. It is a title, the people on it, the record it came
/// from and how long it runs, and every music app worth using — iTunes, Music,
/// Spotify — lays those out as columns you can read down. Lumiere drew a track the
/// same way it drew a folder: a name with a grey line under it, and for audio that
/// line was almost always empty, because it fell back to a series name or a
/// production year and a song has neither. So a playlist of two hundred tracks was
/// two hundred bare filenames, with nothing saying who any of them were by.
///
/// Fixed column widths rather than proportional ones, because the point of a column
/// is that it lines up with the one above it. `ViewThatFits` drops the album first
/// and then the artist as the window narrows, so a track always keeps its title and
/// its length — the two a narrow list cannot do without.
extension ServerBrowserView {

    enum TrackColumn {
        static let number: CGFloat = 28
        /// The title stops growing here. It used to take every point the window
        /// had, which on a wide one left the artist stranded hundreds of points
        /// away from the song it belongs to — two columns that read as unrelated.
        static let titleMax: CGFloat = 460
        /// Artist and album are the ones that stretch now. A minimum rather than a
        /// fixed width, so the slack lands where a long name can use it.
        static let artist: CGFloat = 190
        static let album: CGFloat = 190
        static let artistMax: CGFloat = 320
        static let duration: CGFloat = 48
    }

    /// The header above the tracks, naming the columns beneath it.
    ///
    /// Only where there is more than one track: over a single row it is chrome
    /// One column heading, which is also the control that sorts by it.
    ///
    /// Clicking a heading sorts by that column; clicking the one already sorted
    /// turns it around — the interaction every music app has had since iTunes, and
    /// the reason the headings were drawn as a row of labels in the first place.
    /// The arrow marks the active column, so the list's order is legible without
    /// opening anything.
    ///
    /// The sort itself is the server's. See `TrackSort`.
    @ViewBuilder
    func sortHeader(_ sort: TrackSort, alignment: HorizontalAlignment) -> some View {
        let isActive = scope == .tracks && trackSort == sort
        Button {
            if trackSort == sort {
                trackSortAscending.toggle()
            } else {
                trackSort = sort
                trackSortAscending = sort.defaultAscending
            }
        } label: {
            HStack(spacing: 2) {
                if alignment == .trailing, isActive { sortArrow }
                Text(sort.title)
                if alignment == .leading, isActive { sortArrow }
            }
            .foregroundStyle(
                isActive ? Theme.Palette.accent : Theme.Palette.textMuted
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Only tracks are sorted this way; over an album's own listing the order is
        // the track order and nothing else makes sense.
        .disabled(scope != .tracks)
        .labelledHelp("Sort by \(sort.title)")
    }

    private var sortArrow: some View {
        Image(systemName: trackSortAscending ? "chevron.up" : "chevron.down")
            .font(.system(size: 8, weight: .bold))
    }

    /// explaining nothing, and over an album's own page the columns are obvious.
    @ViewBuilder
    var trackColumnHeader: some View {
        let tracks = entries.filter { $0.item.itemType == .audio }
        if tracks.count > 1 {
            HStack(spacing: Theme.Space.md) {
                // Matches the artwork and number that lead each row, so the labels
                // sit over the columns they name rather than one place to the left.
                Color.clear.frame(width: 40, height: 1)
                Text("#")
                    .frame(width: TrackColumn.number, alignment: .trailing)
                sortHeader(.title, alignment: .leading)
                    .frame(maxWidth: TrackColumn.titleMax, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.md) {
                        sortHeader(.artist, alignment: .leading)
                            .frame(
                                minWidth: TrackColumn.artist,
                                maxWidth: TrackColumn.artistMax, alignment: .leading
                            )
                        sortHeader(.album, alignment: .leading)
                            .frame(
                                minWidth: TrackColumn.album,
                                maxWidth: .infinity, alignment: .leading
                            )
                    }
                    sortHeader(.artist, alignment: .leading)
                        .frame(
                            minWidth: TrackColumn.artist,
                            maxWidth: .infinity, alignment: .leading
                        )
                    EmptyView()
                }
                sortHeader(.duration, alignment: .trailing)
                    .frame(width: TrackColumn.duration, alignment: .trailing)
                // The play chevron's own width, so "Time" is not pushed out over it.
                Color.clear.frame(width: 15, height: 1)
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.Palette.border)
                    .frame(height: 1)
                    .padding(.horizontal, Theme.Space.lg)
            }
        }
    }

    /// One song.
    func trackRow(_ entry: LibraryEntry, indented: Bool) -> some View {
        HStack(spacing: Theme.Space.md) {
            artwork(entry)

            // The track number where the server knows it, and a blank column of the
            // same width where it does not — so a playlist mixing albums that carry
            // numbering with singles that do not still lines up down the page.
            Text(entry.item.indexNumber.map(String.init) ?? "")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .monospacedDigit()
                .frame(width: TrackColumn.number, alignment: .trailing)

            Text(entry.item.name)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: TrackColumn.titleMax, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.md) {
                    artistCell(entry)
                    albumCell(entry)
                }
                artistCell(entry)
                EmptyView()
            }

            if isFavourite(entry) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.accent)
            }

            Text(runtimeText(entry) ?? "")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .monospacedDigit()
                .frame(width: TrackColumn.duration, alignment: .trailing)

            Image(systemName: "play.circle")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .padding(.leading, indented ? Theme.Space.lg + 28 : Theme.Space.lg)
        .padding(.trailing, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm)
        .contentShape(Rectangle())
    }

    /// Everyone on the track, comma-joined. Falls back to the album artist inside
    /// `artistList`, so a compilation still says who is playing.
    private func artistCell(_ entry: LibraryEntry) -> some View {
        Text(entry.item.artistList.joined(separator: ", "))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                minWidth: TrackColumn.artist, maxWidth: TrackColumn.artistMax,
                alignment: .leading
            )
    }

    private func albumCell(_ entry: LibraryEntry) -> some View {
        Text(entry.item.album ?? "")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                minWidth: TrackColumn.album, maxWidth: .infinity, alignment: .leading
            )
    }
}
