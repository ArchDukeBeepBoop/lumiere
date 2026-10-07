import SwiftUI
import LumiereKit

/// Every stream in the chosen file, laid out plainly.
///
/// Infuse has this and it earns its place: when something plays wrong, this is
/// the screen that tells you why. It is also the honest counterpart to the badge
/// row — badges summarise, this states.
struct TechnicalPanel: View {
    let source: MediaSource
    let capabilities: SystemCapabilities

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if let video = source.videoStream {
                        streamGroup("Video", streams: [video])
                    }
                    if !source.audioStreams.isEmpty {
                        streamGroup("Audio", streams: source.audioStreams)
                    }
                    if !source.subtitleStreams.isEmpty {
                        streamGroup("Subtitles", streams: source.subtitleStreams)
                    }
                    fileGroup
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .animation(Theme.Motion.transition, value: isExpanded)
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                Text("Media info")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func streamGroup(_ title: String, streams: [MediaStream]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title.uppercased())
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.Palette.textMuted)
                .tracking(0.6)

            ForEach(streams) { stream in
                VStack(alignment: .leading, spacing: 2) {
                    Text(streamTitle(stream))
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let detail = streamDetail(stream) {
                        Text(detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var fileGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("FILE")
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.Palette.textMuted)
                .tracking(0.6)

            if let container = source.container {
                infoRow("Container", container.uppercased())
            }
            if let size = source.size, size > 0 {
                infoRow("Size", ByteCountFormatter.string(
                    fromByteCount: size, countStyle: .file
                ))
            }
            if let bitrate = source.bitrate, bitrate > 0 {
                infoRow("Bitrate", String(format: "%.1f Mbps", Double(bitrate) / 1_000_000))
            }
            if let path = source.path {
                infoRow("Path", (path as NSString).lastPathComponent)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Space.lg)
            Text(value)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    // MARK: - Stream description

    private func streamTitle(_ stream: MediaStream) -> String {
        if let display = stream.displayTitle, !display.isEmpty { return display }

        var parts: [String] = []
        if let language = stream.language { parts.append(language.uppercased()) }
        if let codec = stream.codec { parts.append(BadgeBuilder.normalise(codec: codec)) }
        if stream.type == .audio {
            let layout = BadgeBuilder.channelLabel(for: stream)
            if !layout.isEmpty { parts.append(layout) }
        }
        return parts.isEmpty ? "Track \(stream.index)" : parts.joined(separator: " · ")
    }

    private func streamDetail(_ stream: MediaStream) -> String? {
        var parts: [String] = []

        switch stream.type {
        case .video:
            if let width = stream.width, let height = stream.height {
                parts.append("\(width) × \(height)")
            }
            if let depth = stream.bitDepth { parts.append("\(depth)-bit") }
            if let range = BadgeBuilder.rangeLabel(for: stream, capabilities: capabilities) {
                parts.append(range)
            }
            if let fps = stream.averageFrameRate ?? stream.realFrameRate {
                parts.append(String(format: "%.3f fps", fps))
            }
            // The one place the app volunteers *why* something will be slow.
            if let note = decodeNote(for: stream) { parts.append(note) }

        case .audio:
            if let rate = stream.sampleRate { parts.append("\(rate / 1000) kHz") }
            if let bitrate = stream.bitRate, bitrate > 0 {
                parts.append("\(bitrate / 1000) kbps")
            }

        case .subtitle:
            if stream.isForced == true { parts.append("Forced") }
            if stream.isExternal == true { parts.append("External") }
            if let codec = stream.codec { parts.append(codec.uppercased()) }

        default:
            break
        }

        if stream.isDefault == true { parts.append("Default") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Whether this Mac will decode the stream in hardware.
    private func decodeNote(for stream: MediaStream) -> String? {
        guard let codec = stream.codec else { return nil }
        return MediaSummary.decodesInHardware(codec: codec, capabilities: capabilities)
            ? nil : "Software decode"
    }
}
