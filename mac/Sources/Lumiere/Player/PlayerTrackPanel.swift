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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabs
            Divider().overlay(Theme.PlayerPalette.surfaceStroke)
            ScrollView {
                VStack(spacing: Theme.Space.xxs) {
                    rows
                }
                .padding(Theme.Space.sm)
            }
            .frame(maxHeight: maxHeight)
        }
        .frame(width: width)
        .playerSurface(cornerRadius: Theme.Radius.playerPanel)
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: Theme.Space.xxs) {
            ForEach(availableTabs) { item in
                Button { tab = item } label: {
                    Text(item.title)
                        .font(Theme.Font.playerTab)
                        .foregroundStyle(
                            tab == item
                                ? Theme.Palette.onPlayerChrome
                                : Theme.Palette.onPlayerChromeSecondary
                        )
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, Theme.Space.xs)
                        .background(
                            Capsule()
                                .fill(Theme.PlayerPalette.controlActive)
                                .opacity(tab == item ? 1 : 0)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button { tab = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labelledHelp("Close")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
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

    @ViewBuilder
    private var audioRows: some View {
        AudioFilterRows(model: model)
        if model.audioTracks.isEmpty {
            emptyNote("This file reports no audio tracks.")
        } else {
            ForEach(model.audioTracks) { track in
                PlayerPanelRow(
                    title: track.title,
                    detail: track.language,
                    selected: model.selectedAudioTrack == track.id
                ) {
                    Task { await model.selectAudioTrack(track.id) }
                }
            }
        }
    }

    private var subtitleRows: some View {
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
                    title: track.title,
                    detail: track.isForced ? "Forced" : track.language,
                    selected: model.selectedSubtitleTrack == track.id
                ) {
                    Task { await model.selectSubtitleTrack(track.id) }
                }
            }
            // Fetching one, and lining it up. See PlayerTrackPanel+Find.swift.
            subtitleTools
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
                    .background(current ? Color.white.opacity(0.08) : .clear)
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

/// One row of the panel.
///
/// The checkmark keeps its column whether or not it is drawn, so a list of tracks
/// has one left edge rather than two. No shadow and no permanent fill: there can
/// be forty of these in a chapter list, and forty shadowed slabs is a wall.
struct PlayerPanelRow: View {
    let title: String
    let detail: String?
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.PlayerPalette.scrubPlayed)
                    .frame(width: 14)
                    .opacity(selected ? 1 : 0)

                Text(title)
                    .font(Theme.Font.playerRow)
                    .foregroundStyle(Theme.Palette.onPlayerChrome)
                    .lineLimit(1)

                Spacer(minLength: Theme.Space.sm)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.Font.playerRow)
                        .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovering ? Theme.PlayerPalette.rowHover
                                     : Theme.PlayerPalette.rowSelected)
                    .opacity(isHovering || selected ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
    }
}
