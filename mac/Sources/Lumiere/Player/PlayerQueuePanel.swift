import SwiftUI
import LumiereKit

/// The season, in order, with the file playing marked.
///
/// Its own panel and its own button on the bar, rather than a fifth tab beside
/// Audio and Subtitles. Two reasons, and the second is the one that matters:
///
/// - It answers a different question. The tracks panel is about *this* file; this is
///   about which file to play, which is the same question the Next Episode button
///   asks and belongs next to it.
/// - It needs the height. A tab strip's panel is sized for four subtitle tracks; a
///   season is twenty-six episodes, and sharing one budget meant the list that needs
///   the room was bounded by the list that does not.
///
/// Selecting a row swaps the file in place — the same call the next-episode button
/// makes — rather than closing the player and opening another, which is the whole
/// point of having it here.
struct PlayerQueuePanel: View {
    let model: PlayerModel
    /// Plays another episode without leaving the player.
    let onPlayEpisode: (LibraryEntry) -> Void
    let onClose: () -> Void
    /// Sized by the caller from the player's own bounds. See `Theme.PlayerMetric`.
    var width: CGFloat = Theme.PlayerMetric.panelWidth
    var maxHeight: CGFloat = Theme.PlayerMetric.panelRowHeight
        * Theme.PlayerMetric.queueTargetRows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.PlayerPalette.surfaceStroke)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.Space.xxs) {
                        rows
                    }
                    .padding(Theme.Space.sm)
                }
                .frame(maxHeight: maxHeight)
                // Opened at episode 4 of 26, a list scrolled to the top is a list
                // you have to search. It opens where you are.
                .onAppear {
                    guard let index = model.queueIndex,
                          model.queue.indices.contains(index) else { return }
                    proxy.scrollTo(model.queue[index].id, anchor: .center)
                }
            }
        }
        .frame(width: width)
        .playerSurface(cornerRadius: Theme.Radius.playerPanel)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("Up Next")
                .font(Theme.Font.playerTab)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
            // What the list holds, since it is now long enough that its own length
            // is not obvious from looking at it.
            Text(countText)
                .font(Theme.Font.playerTab)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labelledHelp("Close")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private var countText: String {
        model.queue.count == 1 ? "1 episode" : "\(model.queue.count) episodes"
    }

    private var rows: some View {
        ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, episode in
            PlayerPanelRow(
                title: episode.item.name,
                detail: episodeDetail(episode, index: index),
                selected: index == model.queueIndex
            ) {
                guard index != model.queueIndex else { return }
                onPlayEpisode(episode)
            }
            .id(episode.id)
        }
    }

    /// "S1E4", plus how far in you already are.
    private func episodeDetail(_ episode: LibraryEntry, index: Int) -> String? {
        var parts: [String] = []
        if let code = episode.item.episodeCode(compact: true) {
            parts.append(code)
        }
        if index == model.queueIndex {
            parts.append("Playing")
        } else if episode.isPlayed {
            parts.append("Watched")
        } else if let progress = episode.progress, progress > 0.01 {
            parts.append("\(Int(progress * 100))%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
