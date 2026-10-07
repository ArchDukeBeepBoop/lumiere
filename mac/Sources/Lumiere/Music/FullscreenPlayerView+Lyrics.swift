import SwiftUI
import LumiereKit

/// Lyrics beside the cover: synced ones follow the song, plain ones scroll.
///
/// Synced lyrics come from the .lrc beside each track. The line being sung is
/// bright and the rest dim, the panel keeps it a little above centre, and
/// clicking a line goes to it — the way Apple Music and Plex draw them.
extension FullscreenPlayerView {

    @ViewBuilder
    var lyricsPanel: some View {
        if isLoadingLyrics {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics, !lyrics.isEmpty {
            if lyrics.first?.start != nil {
                syncedLyrics(lyrics)
            } else {
                ScrollView {
                    Text(lyrics.map(\.text).joined(separator: "\n"))
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("No lyrics for this track")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.textSecondary)
                // Says where they would come from, since the answer is "you put
                // them there" rather than "the app will find them".
                Text("Lumiere does not fetch lyrics. A .lrc file with the track's name "
                   + "beside it is read and synced; or right-click a track, choose "
                   + "Edit Track and paste in lyrics you already have.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func syncedLyrics(_ lines: [LyricLine]) -> some View {
        let current = LyricLine.current(in: lines, at: music.position)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(lines) { line in
                        Button {
                            if let start = line.start { music.seek(to: start) }
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(line.id == current
                                    ? Theme.Palette.textPrimary : Theme.Palette.textMuted)
                                .opacity(line.id == current ? 1 : 0.55)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                    }
                }
                .padding(.vertical, 160)
                .animation(Theme.Motion.hover, value: current)
            }
            .scrollIndicators(.hidden)
            .onChange(of: current) {
                guard let current else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.35))
                }
            }
        }
    }

    func loadLyrics() async {
        guard let client, let id = music.current?.id else { lyrics = nil; return }
        isLoadingLyrics = true
        defer { isLoadingLyrics = false }
        lyrics = await client.lyricLines(itemId: id)
    }
}
