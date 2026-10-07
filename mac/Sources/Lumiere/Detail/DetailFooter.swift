import SwiftUI
import LumiereKit

/// The pinned technical strip at the bottom of a detail page.
///
/// Infuse keeps this visible rather than folding it into a panel, and it earns
/// the space: which server, which file, and what it actually is are the three
/// things you want when something plays badly, and none of them should cost a
/// click to see.
struct DetailFooter: View {
    let serverName: String
    let item: ItemRecord
    let source: MediaSource?
    let capabilities: SystemCapabilities

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 1) {
                Text("on \(serverName)"
                     + (LoosePlacement.wasLoose(season: item.parentIndexNumber, path: item.path)
                        ? " · found loose in the show's folder, so filed under Extras" : ""))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                Text(filename)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: Theme.Space.lg)

            if !technicalParts.isEmpty {
                HStack(spacing: Theme.Space.md) {
                    ForEach(technicalParts, id: \.self) { part in
                        Text(part)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .fixedSize()
            }
        }
        // The page margin, so the filename starts on the same line as the shelf
        // titles above it rather than 8pt to their left.
        .padding(.horizontal, Theme.Space.shelfInset)
        .padding(.vertical, Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tinted with the page: this bar is pinned to the window's foot, over
        // the page most of the time and the hero's dark artwork at the top,
        // and untinted it went a muddy grey there with its text lost.
        .liquidGlass(Rectangle(), tint: Theme.Palette.canvas.opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 1)
        }
    }

    /// Always the real filename here, whatever the title style is set to. The
    /// footer's job is to identify the file on disk; that is the one place the
    /// metadata name would be the wrong answer.
    private var filename: String {
        if let path = source?.path ?? item.path, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return TitleFormatter.metadataFilename(for: item)
    }

    /// `2.3 GB · H.264 · (1080p) · AAC 2.0 · 2.2 Mbps · 24 fps`, in Infuse's order.
    private var technicalParts: [String] {
        guard let source else { return [] }
        var parts: [String] = []

        if let size = source.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let video = source.videoStream {
            if let codec = video.codec {
                parts.append(MediaSummary.normalise(codec: codec))
            }
            if let resolution = MediaSummary.resolutionLabel(
                width: video.width, height: video.height
            ) {
                parts.append("(\(resolution))")
            }
            if let range = MediaSummary.rangeLabel(
                for: video, dolbyVisionSupported: capabilities.dolbyVision
            ) {
                parts.append(range)
            }
        }
        if let audio = source.defaultAudioStream {
            let codec = MediaSummary.normalise(codec: audio.codec ?? "")
            let layout = MediaSummary.channelLabel(for: audio)
            let combined = [codec, layout].filter { !$0.isEmpty }.joined(separator: " ")
            if !combined.isEmpty { parts.append(combined) }
        }
        if let bitrate = source.bitrate, bitrate > 0 {
            parts.append(String(format: "%.1f Mbps", Double(bitrate) / 1_000_000))
        }
        if let fps = source.videoStream?.averageFrameRate ?? source.videoStream?.realFrameRate {
            // Whole numbers read as "24 fps"; 23.976 must keep its decimals or it
            // becomes 24 and stops being the useful distinction it is.
            parts.append(
                fps == fps.rounded()
                    ? String(format: "%.0f fps", fps)
                    : String(format: "%.3f fps", fps)
            )
        }
        return parts
    }
}

/// Community and critic scores, as chips.
struct RatingChips: View {
    let community: Double?
    let critic: Double?

    @Environment(\.isOnArtwork) private var isOnArtwork

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            if let community {
                chip(
                    icon: "star.fill",
                    tint: Theme.Palette.accent,
                    text: Rating.text(community) ?? ""
                )
            }
            if let critic {
                chip(
                    icon: critic >= 60 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill",
                    tint: critic >= 60 ? Theme.Palette.success : Theme.Palette.danger,
                    text: "\(Int(critic))%"
                )
            }
        }
    }

    private func chip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.secondaryText(onArtwork: isOnArtwork))
        }
    }
}
