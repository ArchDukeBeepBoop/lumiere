import SwiftUI
import LumiereKit

/// The queue side of the full player.
///
/// Split from FullscreenPlayerView.swift for the project's 300-line rule. It is
/// also the half that absorbed the docked panel this replaced, which is why it is
/// the larger piece.
extension FullscreenPlayerView {

    /// The queue, with everything the docked panel used to be needed for.
    ///
    /// Artist, duration, a speaker on the row that is playing, and the actions that
    /// only existed in the panel this replaces — star it, add it to a playlist, take
    /// it out of the queue. Absorbing those is what made removing that panel a
    /// simplification rather than a loss.
    var queuePanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(music.queue.enumerated()), id: \.element.id) { index, entry in
                    queueRow(index: index, entry: entry)
                        .contextMenu { queueMenu(index: index, entry: entry) }
                }
            }
        }
    }

    func queueRow(index: Int, entry: LibraryEntry) -> some View {
        let isCurrent = index == music.currentIndex
        return Button { music.jump(to: index) } label: {
            HStack(spacing: Theme.Space.sm) {
                // The playing row shows a speaker where its number would be, which
                // is how every music app marks it and needs no colour to be read.
                Group {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                    } else {
                        Text("\(index + 1)").font(Theme.Font.caption)
                    }
                }
                .foregroundStyle(isCurrent ? Theme.Palette.accent : Theme.Palette.textMuted)
                .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.item.name)
                        .font(Theme.Font.body)
                        .foregroundStyle(isCurrent
                                         ? Theme.Palette.accent : Theme.Palette.textPrimary)
                        .lineLimit(1)
                    if let artist = entry.item.albumArtist ?? entry.item.artists {
                        Text(artist)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.sm)
                if let seconds = entry.item.runtimeSeconds {
                    Text(Timecode.string(seconds))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func queueMenu(index: Int, entry: LibraryEntry) -> some View {
        if let repository {
            let starred = favourites[entry.id] ?? (entry.userData?.isFavorite ?? false)
            Button(starred ? "Remove from Favourites" : "Add to Favourites") {
                favourites[entry.id] = !starred
                Task {
                    let ok = await repository.setFavorite(itemId: entry.id, favorite: !starred)
                    // Put the star back if the server refused, rather than leaving
                    // the row claiming something that did not happen.
                    if ok != true { favourites[entry.id] = starred }
                }
            }
            Button("Add to Playlist…") { playlistTarget = entry }
            Divider()
        }
        Button("Remove from Queue") { music.remove(at: index) }
    }
}
