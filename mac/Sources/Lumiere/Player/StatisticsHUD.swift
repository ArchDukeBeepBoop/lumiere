import SwiftUI
import LumierePlayer

/// The playback stats overlay.
///
/// Exists to answer one question honestly: is this file actually direct playing
/// and decoding in hardware, or has something quietly fallen back? Every field
/// shows "—" when the engine cannot report it, rather than a plausible guess.
struct StatisticsHUD: View {
    let model: PlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Playback")
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.Palette.accent)
                .tracking(0.6)

            row("Engine", model.statistics.engineName)
            row("Decode", model.statistics.decodePath)
            if let decision = model.decision {
                row("Route", decision.badgeText)
            }
            row("Video", model.statistics.videoCodec)
            row("Audio", model.statistics.audioCodec)
            row("Size", model.statistics.resolution)
            row("FPS", fpsText)
            row("Dropped", model.statistics.droppedFrames.map(String.init))
            row("Bitrate", bitrateText)
            row("Buffer", model.statistics.cacheSeconds.map { String(format: "%.1f s", $0) })
        }
        .padding(Theme.Space.md)
        // The same plate the transport bar sits on, so the two overlays read as
        // parts of one player rather than as two separate widgets.
        .playerSurface(cornerRadius: Theme.Radius.playerPanel)
        .padding(.horizontal, Theme.Space.shelfInset)
        // Below the Close button rather than under it: the HUD opens in the same
        // corner, and at the old inset the two overlapped.
        .padding(.top, Theme.PlayerMetric.hudTopInset)
        .padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
    }

    private var fpsText: String? {
        guard let estimated = model.statistics.estimatedFPS else {
            return model.statistics.containerFPS.map { String(format: "%.3f", $0) }
        }
        guard let container = model.statistics.containerFPS else {
            return String(format: "%.1f", estimated)
        }
        // Both numbers matter: the container rate is what the file claims, the
        // estimate is what is actually being rendered. A gap between them is the
        // symptom of a machine that cannot keep up.
        return String(format: "%.1f / %.3f", estimated, container)
    }

    private var bitrateText: String? {
        guard let video = model.statistics.videoBitrate, video > 0 else { return nil }
        let mbps = Double(video) / 1_000_000
        guard let audio = model.statistics.audioBitrate, audio > 0 else {
            return String(format: "%.1f Mbps", mbps)
        }
        return String(format: "%.1f + %.0f kbps", mbps, Double(audio) / 1000)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack(spacing: Theme.Space.md) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                .frame(width: 58, alignment: .leading)
            Text(value ?? "—")
                .font(Theme.Font.timecode)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
            Spacer(minLength: 0)
        }
    }
}
