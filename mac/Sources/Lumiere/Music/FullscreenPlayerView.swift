import SwiftUI
import LumiereKit

/// The music player filling the window: large artwork, the scrubber, and the
/// lyrics or queue beside it.
///
/// A third size rather than a second one. The mini bar is for the album you have
/// already chosen and are no longer thinking about; the expanded panel is for
/// reaching the queue without leaving what you were doing. This is for when the
/// music *is* what you are doing — the cover at a size worth looking at, and room
/// for the words.
struct FullscreenPlayerView: View {
    let music: MusicPlayerModel
    let pipeline: ImagePipeline
    let serverURL: URL
    /// Read live from the server: lyrics are not part of the item payload and are
    /// not cached, since a track's lyrics are large next to its metadata and are
    /// only ever wanted for the one thing playing.
    var client: JellyfinClient?
    /// For the queue's own actions — starring a track, listing playlists. Optional
    /// like everywhere else: without one the menu offers only what it can honour.
    var repository: LibraryRepository?
    let onClose: () -> Void

    private enum Side: String, CaseIterable, Identifiable {
        case lyrics, queue
        var id: String { rawValue }
        var title: String { self == .lyrics ? "Lyrics" : "Queue" }
    }

    @State private var side: Side = .lyrics
    // Not private: the lyrics panel lives in FullscreenPlayerView+Lyrics.swift.
    @State var lyrics: [LyricLine]?
    @State var isLoadingLyrics = false
    /// Optimistic stars, so the menu answers the click rather than the round trip.
    /// Not private: the queue rows that read them live in
    /// FullscreenPlayerView+Queue.swift, and Swift scopes `private` to the file.
    @State var favourites: [String: Bool] = [:]
    @State var playlistTarget: LibraryEntry?
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: music.current?.id) { await loadLyrics() }
        .sheet(item: $playlistTarget) { target in
            if let repository {
                AddToPlaylistSheet(
                    itemIds: [target.id],
                    itemName: target.item.name,
                    repository: repository,
                    onDone: { playlistTarget = nil }
                )
            }
        }
    }

    /// The cover, enormous and blurred, as the room's lighting.
    ///
    /// Drawn from the same cached image the foreground uses rather than a second
    /// fetch at a second size — one decode, and the blur hides that it is being
    /// scaled well past its pixel size.
    @ViewBuilder
    private var backdrop: some View {
        if let entry = music.current {
            RemoteImage(
                request: .poster(for: entry, serverURL: serverURL, width: 320, scale: scale),
                pipeline: pipeline
            )
            .scaledToFill()
            .blur(radius: 90, opaque: true)
            .overlay(Theme.Palette.canvas.opacity(0.72))
            .clipped()
            .ignoresSafeArea()
        } else {
            Theme.Palette.canvas.ignoresSafeArea()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .labelledHelp("Back to browsing")
                Spacer()
            }
            .padding(Theme.Space.lg)

            HStack(alignment: .center, spacing: Theme.Space.xxxl) {
                nowPlaying
                sidePanel
            }
            .padding(.horizontal, Theme.Space.xxxl)
            .padding(.bottom, Theme.Space.xxxl)
            .frame(maxWidth: 1200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let entry = music.current {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                RemoteImage(
                    request: .poster(for: entry, serverURL: serverURL, width: 380, scale: scale),
                    pipeline: pipeline
                )
                .frame(width: 380, height: 380)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.item.name)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                    if let artist = entry.item.seriesName {
                        Text(artist)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .frame(width: 380, alignment: .leading)

                scrubber
                transport
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : music.position },
                    // While dragging the slider follows the pointer, not the
                    // player — otherwise each tick yanks the handle back.
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(music.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { music.seek(to: scrubPosition) }
                }
            )
            .tint(Theme.Palette.accent)

            HStack {
                Text(timecode(isScrubbing ? scrubPosition : music.position))
                Spacer()
                Text(timecode(music.duration))
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
        }
        .frame(width: 380)
    }

    private var transport: some View {
        HStack(spacing: Theme.Space.xl) {
            control("shuffle", isOn: music.isShuffled) { music.toggleShuffle() }
            control("backward.fill", size: 20) { music.previous() }
                .disabled(!music.canGoBack)

            Button { music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Palette.playButtonLabel)
                    .frame(width: 58, height: 58)
                    .background(Theme.Palette.playButton, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            control("forward.fill", size: 20) { music.next() }
                .disabled(!music.canGoForward)
            control(music.repeatMode.icon, isOn: music.repeatMode != .off) {
                music.cycleRepeat()
            }
        }
        .frame(width: 380)
    }

    private func control(
        _ icon: String, size: CGFloat = 16, isOn: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Picker("", selection: $side) {
                ForEach(Side.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 200)

            if side == .lyrics { lyricsPanel } else { queuePanel }
        }
        .frame(maxWidth: .infinity, maxHeight: 520, alignment: .topLeading)
    }

    /// Forwards to the one implementation. See `Timecode`.
    private func timecode(_ seconds: Double) -> String {
        Timecode.string(seconds)
    }
}
