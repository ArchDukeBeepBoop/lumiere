import SwiftUI
import LumiereKit

/// The always-there strip along the bottom while music is queued.
///
/// The whole point of a music player is that it survives navigation: you start an
/// album, then go looking at something else, and it keeps going. A sheet or a route
/// could not do that — both are things you are either on or not — so this lives
/// outside the navigation stack entirely, as an inset on the shell.
struct MiniPlayerBar: View {
    @Bindable var music: MusicPlayerModel
    let pipeline: ImagePipeline
    let serverURL: URL

    @Environment(\.displayScale) private var scale
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0

    var body: some View {
        if let entry = music.current {
            VStack(spacing: 0) {
                progressLine
                HStack(spacing: Theme.Space.md) {
                    artwork(entry)
                    titles(entry)
                    Spacer(minLength: Theme.Space.md)
                    transport
                    Divider().frame(height: 22)
                    volumeControl
                    Divider().frame(height: 22)
                    modes
                    expandButton
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.sm)
            }
            .liquidGlass(Rectangle())
            .overlay(alignment: .top) { Divider() }
        }
    }

    /// A hairline across the very top of the bar rather than a slider in the row.
    /// It is a progress *indicator* at this size — the real scrubber lives in the
    /// expanded view, where there is room to hit it.
    private var progressLine: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.Palette.border)
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 2)
    }

    private var fraction: Double {
        guard music.duration > 0 else { return 0 }
        return min(1, max(0, music.position / music.duration))
    }

    private func artwork(_ entry: LibraryEntry) -> some View {
        RemoteImage(
            request: .poster(for: entry, serverURL: serverURL, width: 36, scale: scale),
            pipeline: pipeline
        )
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge))
    }

    private func titles(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.item.name)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Text(subtitle(entry))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private func subtitle(_ entry: LibraryEntry) -> String {
        var parts: [String] = []
        if let artist = entry.item.seriesName { parts.append(artist) }
        parts.append(timecode(music.position) + " / " + timecode(music.duration))
        return parts.joined(separator: " · ")
    }

    private var transport: some View {
        HStack(spacing: Theme.Space.sm) {
            iconButton("backward.fill", size: 13) { music.previous() }
                .disabled(!music.canGoBack)
            iconButton(music.isPlaying ? "pause.fill" : "play.fill", size: 17) {
                music.togglePlayPause()
            }
            iconButton("forward.fill", size: 13) { music.next() }
                .disabled(!music.canGoForward)
        }
    }

    /// Its own control rather than deferring to the system volume, which would
    /// duck every other app on the machine along with it.
    private var volumeControl: some View {
        HStack(spacing: Theme.Space.xs) {
            Button { music.toggleMute() } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labelledHelp(music.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { music.isMuted ? 0 : music.volume },
                    // Moving the slider off zero is itself an unmute — leaving it
                    // muted while the handle sits at half reads as a broken control.
                    set: { newValue in
                        music.isMuted = false
                        music.volume = newValue
                    }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(Theme.Palette.accent)
            .frame(width: 76)
        }
    }

    private var volumeIcon: String {
        if music.isMuted || music.volume <= 0.001 { return "speaker.slash.fill" }
        if music.volume < 0.34 { return "speaker.fill" }
        if music.volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    private var modes: some View {
        HStack(spacing: Theme.Space.sm) {
            iconButton("shuffle", size: 12, isOn: music.isShuffled) { music.toggleShuffle() }
            iconButton(
                music.repeatMode.icon, size: 12, isOn: music.repeatMode != .off
            ) {
                music.cycleRepeat()
            }
        }
    }

    /// Two sizes up from here, and they answer different questions: the panel
    /// One control, one destination.
    ///
    /// There were two: a chevron that raised a 420pt panel over the window, and an
    /// arrow that opened the full player. The panel was a strict subset of the full
    /// player — same now-playing block, same scrubber, same queue — so the app had
    /// three presentations of one player and two of them did the same job. Apple
    /// Music has two, the bar and the full screen, and so does this now.
    private var expandButton: some View {
        iconButton("chevron.up", size: 12) {
            music.isFullscreen = true
        }
        .labelledHelp("Open the full player")
    }

    private func iconButton(
        _ name: String,
        size: CGFloat,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Forwards to the one implementation. See `Timecode`.
    private func timecode(_ seconds: Double) -> String {
        Timecode.string(seconds)
    }
}
