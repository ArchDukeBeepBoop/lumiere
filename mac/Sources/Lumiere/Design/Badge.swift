import SwiftUI
import LumiereKit

/// The technical chips — 4K DV, TrueHD 7.1, Direct play.
///
/// Colour carries meaning here rather than decoration: video properties are gold,
/// audio is green, the playback route is blue, everything else is neutral. That
/// makes "will this direct play?" answerable at a glance, which is the single
/// most useful thing a badge row can do in a media client.
struct Badge: View {
    let text: String
    var role: Role = .neutral

    enum Role {
        case video, audio, stream, neutral

        var foreground: Color {
            switch self {
            case .video: return Theme.Palette.badgeVideo
            case .audio: return Theme.Palette.badgeAudio
            case .stream: return Theme.Palette.badgeStream
            case .neutral: return Theme.Palette.badgeNeutral
            }
        }

        var border: Color {
            switch self {
            case .video: return Theme.Palette.badgeVideoBorder
            case .audio: return Theme.Palette.badgeAudioBorder
            case .stream: return Theme.Palette.badgeStreamBorder
            case .neutral: return Theme.Palette.badgeNeutralBorder
            }
        }
    }

    var body: some View {
        Text(text)
            .font(Theme.Font.badge)
            .foregroundStyle(role.foreground)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.badge)
                    .strokeBorder(role.border, lineWidth: 1)
            }
    }
}

/// Derives the badge row from a media source.
///
/// Pure and in the app layer rather than LumiereKit because it is presentation:
/// what to *show*. What to *do* about a Dolby Vision file is `PlaybackDecision`,
/// which lands in phase 5.
enum BadgeBuilder {

    static func badges(for source: MediaSource?, capabilities: SystemCapabilities) -> [(String, Badge.Role)] {
        guard let source else { return [] }
        var result: [(String, Badge.Role)] = []

        if let video = source.videoStream {
            if let resolution = resolutionLabel(width: video.width, height: video.height) {
                result.append((resolution, .video))
            }
            if let range = rangeLabel(for: video, capabilities: capabilities) {
                result.append((range, .video))
            }
            if let codec = video.codec?.uppercased() {
                result.append((normalise(codec: codec), .video))
            }
        }

        if let audio = source.defaultAudioStream {
            let codec = normalise(codec: audio.codec?.uppercased() ?? "")
            let layout = channelLabel(for: audio)
            result.append(([codec, layout].compactMap { $0.isEmpty ? nil : $0 }.joined(separator: " "), .audio))
        }

        if let container = source.container?.uppercased(), !container.isEmpty {
            result.append((container, .neutral))
        }

        return result
    }

    /// These delegate to `MediaSummary` in LumiereKit, where they are unit-tested.
    /// The view layer owns only the colour-role mapping above.
    static func resolutionLabel(width: Int?, height: Int?) -> String? {
        MediaSummary.resolutionLabel(width: width, height: height)
    }

    static func rangeLabel(for video: MediaStream, capabilities: SystemCapabilities) -> String? {
        MediaSummary.rangeLabel(for: video, dolbyVisionSupported: capabilities.dolbyVision)
    }

    static func channelLabel(for audio: MediaStream) -> String {
        MediaSummary.channelLabel(for: audio)
    }

    static func normalise(codec: String) -> String {
        MediaSummary.normalise(codec: codec)
    }
}
