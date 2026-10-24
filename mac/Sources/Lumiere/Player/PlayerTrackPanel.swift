import SwiftUI
import LumiereKit

/// Audio, subtitles, speed and chapters, as a panel rather than a system menu.
///
/// The old control was a `Menu`, which draws AppKit's own pop-up: system font,
/// system metrics, a checkmark column that ignores everything in `Theme`, and a
/// window that opens outside the player entirely. Over a film it read as a
/// different application's menu, which is exactly the seam this rebuild is closing.
///
/// Drawn inside the player's own view tree on purpose, not as a `.popover`: an
/// AppKit popover takes first responder, and first responder is what the entire
/// keyboard grammar hangs off — see `KeyCaptureView`.
struct PlayerTrackPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case info, audio, subtitles, speed, chapters

        var id: String { rawValue }

        var title: String {
            switch self {
            case .info: return "Info"
            case .audio: return "Audio"
            case .subtitles: return "Subtitles"
            case .speed: return "Speed"
            case .chapters: return "Chapters"
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .audio: return "speaker.wave.2"
            case .subtitles: return "captions.bubble"
            case .speed: return "gauge.with.dots.needle.67percent"
            case .chapters: return "list.bullet.rectangle"
            }
        }
    }

    let model: PlayerModel
    @Binding var tab: Tab?
    /// Sized by the caller from the player's own bounds. See `Theme.PlayerMetric`.
    var width: CGFloat = Theme.PlayerMetric.panelWidth
    var maxHeight: CGFloat = Theme.PlayerMetric.panelMaxHeight
    /// For chapter pictures, from the scrubbing previews. Without them the
    /// chapters are a list of names, as before.
    var pipeline: ImagePipeline? = nil
    var serverURL: URL? = nil

    /// Speeds worth one click. The same ladder the settings panel offers, so the
    /// two never disagree about what a step is.
    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    @State private var contentHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    rows
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.bottom, Theme.Space.sm)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            // As tall as its rows, up to the limit — not the limit always. Two
            // audio tracks were floating in a box sized for a season.
            .frame(height: min(max(contentHeight, 1), maxHeight))
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: width)
        .playerSurface(cornerRadius: Theme.Radius.playerGlass)
        .environment(\.colorScheme, .dark)
    }

    /// Two columns where there is room, as Apple TV's Audio menu has them:
    /// what to listen to on the left, how it sounds on the right.
    private var isWide: Bool { width >= 440 }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            PlayerSegmented(
                items: availableTabs,
                selection: Binding(get: { tab ?? .audio }, set: { tab = $0 }),
                title: { $0.title },
                icon: isWide ? { $0.icon } : nil
            )
            .fixedSize()
            Spacer(minLength: 0)
            Button { tab = nil } label: {
                Image(systemName: "xmark")
                    .font(Theme.Glyph.sm(.bold))
                    .foregroundStyle(Theme.Palette.onPlayerChrome)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.PlayerPalette.segmentTrack))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .labelledHelp("Close")
        }
        .padding(Theme.Space.sm)
    }

    /// Side by side when wide, one above the other when not.
    @ViewBuilder
    private func columns<L: View, R: View>(_ left: String, _ right: String,
                                           @ViewBuilder leading: () -> L,
                                           @ViewBuilder trailing: () -> R) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: 2) { PlayerSectionLabel(left); leading() }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle().fill(Theme.PlayerPalette.surfaceStroke).frame(width: 1)
                VStack(alignment: .leading, spacing: 2) { PlayerSectionLabel(right); trailing() }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            PlayerSectionLabel(left)
            leading()
            PlayerSectionLabel(right)
            trailing()
        }
    }

    /// Chapters only where the file has any, so the tab strip never offers a page
    /// that says "none".
    private var availableTabs: [Tab] {
        Tab.allCases.filter { item in
            switch item {
            case .chapters: return !model.chapters.isEmpty
            default: return true
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch tab ?? .audio {
        case .info: PlayerInfoRows(model: model)
        case .audio: audioRows
        case .subtitles: subtitleRows
        case .speed: speedRows
        case .chapters: chapterRows
        }
    }

    private var audioRows: some View {
        columns("Language", "Sound") {
            if model.audioTracks.isEmpty {
                emptyNote("This file reports no audio tracks.")
            } else {
                ForEach(model.audioTracks) { track in
                    PlayerPanelRow(
                        title: trackName(track.language, fallback: track.title),
                        detail: nil,
                        subtitle: TrackDetail.line(codec: track.codec, channels: track.channels,
                                                   isDefault: track.isDefault, isForced: false),
                        selected: model.selectedAudioTrack == track.id
                    ) {
                        Task { await model.selectAudioTrack(track.id) }
                    }
                }
            }
        } trailing: {
            AudioFilterRows(model: model)
        }
    }

    /// "Japanese", not "jpn"; the file's own title where it names no language.
    private func trackName(_ language: String?, fallback: String) -> String {
        language.flatMap(DetailAbout.languageName) ?? fallback
    }

    private var subtitleRows: some View {
        columns("Subtitles", "Find & Sync") { subtitleList } trailing: { subtitleTools }
    }

    private var subtitleList: some View {
        Group {
            PlayerPanelRow(
                title: "Off",
                detail: nil,
                selected: model.selectedSubtitleTrack == nil
            ) {
                Task { await model.selectSubtitleTrack(nil) }
            }
            ForEach(model.subtitleTracks) { track in
                PlayerPanelRow(
                    title: trackName(track.language, fallback: track.title),
                    detail: nil,
                    subtitle: [track.title == trackName(track.language, fallback: track.title) ? nil : track.title,
                               TrackDetail.line(codec: track.codec, channels: nil,
                                                isDefault: track.isDefault, isForced: track.isForced)]
                        .compactMap { $0 }.joined(separator: " · "),
                    selected: model.selectedSubtitleTrack == track.id
                ) {
                    Task { await model.selectSubtitleTrack(track.id) }
                }
            }
        }
    }

    private var speedRows: some View {
        ForEach(speeds, id: \.self) { speed in
            PlayerPanelRow(
                title: speed == 1 ? "Normal" : String(format: "%.2f×", speed),
                detail: nil,
                selected: abs(model.playbackSpeed - speed) < 0.001
            ) {
                Task { await model.setPlaybackSpeed(speed) }
            }
        }
    }

    @ViewBuilder
    private var chapterRows: some View {
        if let pipeline, let serverURL, model.trickplay != nil {
            // Pictures, as Apple TV's Chapters tab shows them: each chapter
            // a frame from a few seconds in, its name and time beside it.
            ForEach(Array(model.chapters.enumerated()), id: \.offset) { index, chapter in
                let current = model.currentChapter?.startSeconds == chapter.startSeconds
                Button { Task { await model.jumpToChapter(chapter) } } label: {
                    HStack(spacing: Theme.Space.md) {
                        TrickplayPreview(model: model, serverURL: serverURL, pipeline: pipeline,
                                         itemId: model.itemId, seconds: chapter.startSeconds + 5,
                                         fixedWidth: 128)
                            .frame(width: 128)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.name ?? "Chapter \(index + 1)")
                                .font(Theme.Font.playerRow.weight(current ? .semibold : .regular))
                                .foregroundStyle(Theme.Palette.onPlayerChrome)
                                .lineLimit(2)
                            Text(PlayerModel.timecode(chapter.startSeconds))
                                .font(Theme.Font.trickplayTimecode)
                                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.xs)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(current ? Theme.PlayerPalette.menuSelected : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else {
            chapterNames
        }
    }

    private var chapterNames: some View {
        ForEach(Array(model.chapters.enumerated()), id: \.offset) { index, chapter in
            PlayerPanelRow(
                title: chapter.name ?? "Chapter \(index + 1)",
                detail: PlayerModel.timecode(chapter.startSeconds),
                selected: model.currentChapter?.startSeconds == chapter.startSeconds
            ) {
                Task { await model.jumpToChapter(chapter) }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.playerRow)
            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
    }
}
