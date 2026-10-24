import SwiftUI
import LumiereKit

/// Apple TV's Up Next: at the credits the picture steps back into a corner,
/// still playing, and the next episode takes the screen — its picture, its
/// name, a countdown when it will start by itself, and two choices. Keep
/// Watching brings the credits back full size.
struct UpNextStage: View {
    let next: LibraryEntry
    let pipeline: ImagePipeline
    let serverURL: URL
    let isPlaying: Bool
    let onPlayNow: () -> Void
    let onKeepWatching: () -> Void

    @AppStorage(Preference.playsNextAutomatically.name) private var autoplays
        = Preference.playsNextAutomatically.defaultValue
    @State private var countdown: Int?
    @Environment(\.displayScale) private var scale

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Up Next")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                RemoteImage(
                    request: .backdrop(for: next, serverURL: serverURL, width: 520, scale: scale),
                    pipeline: pipeline
                )
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: 520, height: 292)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                VStack(alignment: .leading, spacing: 4) {
                    if let series = next.item.seriesName {
                        Text(series).font(Theme.Font.detailMeta).foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    }
                    Text(episodeLine)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.onPlayerChrome)
                        .lineLimit(2)
                    if let overview = next.item.overview {
                        Text(overview)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                            .lineLimit(3)
                    }
                }
                .frame(width: 520, alignment: .leading)
                HStack(spacing: Theme.Space.md) {
                    Button(action: onPlayNow) {
                        Text(countdown.map { "Play Now · \($0)" } ?? "Play Now")
                            .font(Theme.Font.playLabel)
                            .foregroundStyle(Theme.PlayerPalette.segmentOnThumb)
                            .padding(.horizontal, Theme.Space.xl)
                            .padding(.vertical, Theme.Space.md)
                            .background(Theme.PlayerPalette.segmentThumb, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    Button(action: onKeepWatching) {
                        Text("Keep Watching")
                            .font(Theme.Font.playLabel)
                            .foregroundStyle(Theme.Palette.onPlayerChrome)
                            .padding(.horizontal, Theme.Space.xl)
                            .padding(.vertical, Theme.Space.md)
                            .background(Theme.PlayerPalette.menuHover, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.85)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .task(id: isPlaying) { await countDown() }
    }

    private var episodeLine: String {
        let number = [next.item.parentIndexNumber.map { "S\($0)" }, next.item.indexNumber.map { "E\($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        return number.isEmpty ? next.item.name : "\(number)  \(next.item.name)"
    }

    /// The same ten seconds, paused with the picture, and the same "Still
    /// watching?" limit as the small offer it stands in for.
    private func countDown() async {
        guard autoplays, SleepTimer.mode != .afterEpisode, !StillWatching.isAsking else {
            countdown = nil
            return
        }
        if countdown == nil { countdown = 10 }
        while isPlaying, let left = countdown, left > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, isPlaying else { return }
            countdown = left - 1
        }
        if countdown == 0 {
            countdown = nil
            if StillWatching.mayAdvance() { onPlayNow() }
        }
    }
}
