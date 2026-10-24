import SwiftUI

/// The volume bar under the transport, as Apple Music has it: a quiet speaker
/// at one end, a loud one at the other, the slider between. The window's own
/// volume, not the Mac's — the same control the mini player carries.
extension FullscreenPlayerView {
    var volumeRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Button { music.toggleMute() } label: {
                Image(systemName: music.isMuted || music.volume <= 0.001 ? "speaker.slash.fill" : "speaker.fill")
                    .font(Theme.Glyph.md())
                    .frame(width: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labelledHelp(music.isMuted ? "Unmute" : "Mute")
            Slider(
                value: Binding(
                    get: { music.isMuted ? 0 : music.volume },
                    set: { music.isMuted = false; music.volume = $0 }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(Theme.Palette.textSecondary)
            Image(systemName: "speaker.wave.3.fill")
                .font(Theme.Glyph.md())
                .frame(width: 22)
        }
        .foregroundStyle(Theme.Palette.textMuted)
        .frame(maxWidth: 360)
        .padding(.top, Theme.Space.sm)
    }
}
