import SwiftUI
import LumiereKit

/// The rows themselves: a plain item, a collapsed series, and the small pieces of
/// text beside each.
///
/// Split out of ServerBrowserView.swift to keep it under the project's 300-line
/// limit — adding the music scopes and playlist grouping pushed it past.
extension ServerBrowserView {

    /// A collapsed run of one show's episodes. Opens in place rather than pushing a
    /// screen: the playlist's order is the thing being read, and navigating away to
    /// see four of its rows would lose that.
    func seriesRow(id: String, name: String, episodes: [LibraryEntry]) -> some View {
        HStack(spacing: 0) {
            // Removing a whole show in one action. A playlist that collected a
            // season is twelve separate removals otherwise, and the row that
            // collapsed them is the obvious place to undo the collecting.
            if isEditingPlaylist {
                let entryIds = episodes.compactMap { playlistEntryIds[$0.id] }
                Button {
                    Task { await removeFromPlaylist(entryIds: entryIds) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.danger)
                }
                .buttonStyle(.plain)
                .padding(.leading, Theme.Space.lg)
                .disabled(entryIds.isEmpty)
                .labelledHelp("Remove all \(episodes.count) episodes of \(name) from this "
                    + "playlist. The files are untouched.")
            }
            seriesDisclosure(id: id, name: name, episodes: episodes)
        }
    }

    private func seriesDisclosure(
        id: String, name: String, episodes: [LibraryEntry]
    ) -> some View {
        Button {
            if expandedSeries.contains(id) {
                expandedSeries.remove(id)
            } else {
                expandedSeries.insert(id)
            }
        } label: {
            HStack(spacing: Theme.Space.md) {
                if let first = episodes.first { artwork(first) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text("\(episodes.count) episodes")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: expandedSeries.contains(id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A list rather than a grid. Music is read as text — artist, album, track name,
    /// in order — and a poster wall of identical album covers is harder to scan than
    /// the names are.
    func row(_ entry: LibraryEntry, indented: Bool = false) -> some View {
        HStack(spacing: 0) {
            // Edit mode's remove control sits outside the row button rather than
            // inside it, so the click that deletes can never be the click that plays.
            if isEditingPlaylist, let entryId = playlistEntryIds[entry.id] {
                Button {
                    Task { await removeFromPlaylist(entryId: entryId) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.danger)
                }
                .buttonStyle(.plain)
                .padding(.leading, Theme.Space.lg)
                .labelledHelp("Remove from this playlist. The file is untouched.")
            }
            playableRow(entry, indented: indented)
        }
    }

    private func playableRow(_ entry: LibraryEntry, indented: Bool) -> some View {
        Button {
            if entry.item.isFolder {
                path.append((id: entry.item.id, name: entry.item.name, kind: entry.item.itemType))
            } else if entry.item.itemType == .audio, let onPlayAudio {
                // The rest of what is on screen is queued behind it, so clicking a
                // track inside an album plays the album from there rather than
                // stopping after one song.
                let tracks = entries.filter { $0.item.itemType == .audio }
                let index = tracks.firstIndex { $0.id == entry.id } ?? 0
                onPlayAudio(tracks, index)
            } else {
                onPlay(entry.item.id)
            }
        } label: {
            // A song gets columns; everything else keeps the name-and-subtitle row,
            // which is the right shape for a folder, an album or an artist.
            if entry.item.itemType == .audio {
                trackRow(entry, indented: indented)
            } else {
                containerRow(entry, indented: indented)
            }
        }
        .buttonStyle(.plain)
    }

    private func containerRow(_ entry: LibraryEntry, indented: Bool) -> some View {
        HStack(spacing: Theme.Space.md) {
                artwork(entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.item.name)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    if let subtitle = subtitle(for: entry) {
                        Text(subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Only when starred: an empty star on every row of a 4,000-track
                // library is noise, and the menu is where one gets set.
                if offersMusicActions, isFavourite(entry) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.accent)
                }
                if let runtime = runtimeText(entry) {
                    Text(runtime)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                Image(systemName: entry.item.isFolder ? "chevron.right" : "play.circle")
                    .font(.system(size: entry.item.isFolder ? 11 : 15))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.leading, indented ? Theme.Space.lg + 28 : Theme.Space.lg)
            .padding(.trailing, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .contentShape(Rectangle())
    }

    func artwork(_ entry: LibraryEntry) -> some View {
        RemoteImage(
            request: .poster(for: entry, serverURL: serverURL, width: 40, scale: scale),
            pipeline: pipeline
        )
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.badge)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
    }

    /// Whatever identifies the row beyond its name — the artist for a track, the
    /// child count for a container.
    func subtitle(for entry: LibraryEntry) -> String? {
        if let series = entry.item.seriesName { return series }
        if entry.item.isFolder, let count = entry.item.childCount, count > 0 {
            return "\(count) item\(count == 1 ? "" : "s")"
        }
        if let year = entry.item.productionYear { return String(year) }
        return nil
    }

    func runtimeText(_ entry: LibraryEntry) -> String? {
        guard let seconds = entry.item.runtimeSeconds, seconds > 0 else { return nil }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
