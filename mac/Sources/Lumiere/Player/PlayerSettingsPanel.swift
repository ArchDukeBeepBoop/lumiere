import SwiftUI
import LumiereKit
import LumierePlayer

/// The gear panel: two columns, categories on the left with their current value
/// beneath, options on the right. Laid out as Infuse has it, because showing the
/// current value in the list is what makes it usable without opening each one.
struct PlayerSettingsPanel: View {
    let model: PlayerModel
    @Binding var isPresented: Bool

    @State private var section: Section = .aspectRatio

    /// The player's own size, so the panel can take a share of it rather than a
    /// constant. Zero until the first layout, which the metric handles.
    var playerSize: CGSize = .zero

    var body: some View {
        let size = Theme.PlayerMetric.settingsPanelSize(in: playerSize)
        return HStack(spacing: 0) {
            categories
            Rectangle().fill(Theme.PlayerPalette.surfaceStroke).frame(width: 1)
            options
        }
        .frame(width: size.width, height: size.height)
        // The same smoked glass as every other panel over the film. It was an
        // opaque page-coloured sheet: white over a dark scene in light mode,
        // and the one panel that looked like a different app.
        .playerSurface(cornerRadius: Theme.Radius.playerGlass)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Left column

    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.onPlayerChrome)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.PlayerPalette.segmentTrack))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(Theme.Space.md)

            PlayerSectionLabel("Picture & Playback")
                .padding(.horizontal, Theme.Space.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Section.allCases) { item in
                        categoryRow(item)
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 230)
    }

    private func categoryRow(_ item: Section) -> some View {
        let disabled = item.needsVideoAdjustments && !model.supportsVideoAdjustments

        return Button {
            section = item
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.PlayerPalette.glyphPlate))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(Theme.Font.playerRow.weight(.medium))
                    Text(currentValue(item))
                        .font(Theme.Font.playerDetail)
                        .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Theme.Palette.onPlayerChrome)
            .opacity(disabled ? 0.45 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(section == item ? Theme.PlayerPalette.menuHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .labelledHelp(disabled ? "Only available on the mpv engine." : "")
    }

    private func currentValue(_ item: Section) -> String {
        if item.needsVideoAdjustments && !model.supportsVideoAdjustments {
            return "Unavailable on this engine"
        }
        switch item {
        case .aspectRatio: return model.aspectOverride.title
        case .verticalShift:
            return model.verticalShift == 0
                ? "None" : String(format: "%+.0f%%", model.verticalShift * 100)
        case .flip:
            switch (model.flipHorizontal, model.flipVertical) {
            case (false, false): return "None"
            case (true, false): return "Horizontal"
            case (false, true): return "Vertical"
            case (true, true): return "Both"
            }
        case .chapters: return model.currentChapter?.name ?? "None"
        case .playbackSpeed:
            return model.playbackSpeed == 1 ? "Normal" : String(format: "%.2f×", model.playbackSpeed)
        case .subtitleStyle: return model.subtitleStyle.title
        case .subtitleSize: return model.subtitleSize.title
        case .subtitleDelay:
            return model.subtitleDelay == 0
                ? "In sync" : String(format: "%+.1f s", model.subtitleDelay)
        case .upscaling: return model.upscaling.title
        case .loop: return model.isLooping ? "On" : "Off"
        case .ambientMode: return model.ambientMode ? "On" : "Off"
        case .statistics: return model.showsStatisticsHUD ? "On" : "Off"
        }
    }

    // MARK: - Right column

    private var options: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(Theme.Font.playerTitle)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)

            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    switch section {
                    case .aspectRatio: aspectOptions
                    case .verticalShift: verticalShiftOptions
                    case .flip: flipOptions
                    case .chapters: chapterOptions
                    case .playbackSpeed: speedOptions
                    case .subtitleStyle: subtitleStyleOptions
                    case .subtitleSize: subtitleSizeOptions
                    case .subtitleDelay: subtitleDelayOptions
                    case .upscaling: upscalingOptions
                    case .loop: loopOptions
                    case .ambientMode: ambientOptions
                    case .statistics: statisticsOptions
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.lg)
            }
        }
    }

    private var aspectOptions: some View {
        ForEach(AspectOverride.allCases) { option in
            optionRow(option.title, selected: model.aspectOverride == option) {
                Task { await model.setAspect(option) }
            }
        }
    }

    private var verticalShiftOptions: some View {
        ForEach([-0.2, -0.1, -0.05, 0.0, 0.05, 0.1, 0.2], id: \.self) { value in
            optionRow(
                value == 0 ? "None" : String(format: "%+.0f%%", value * 100),
                selected: abs(model.verticalShift - value) < 0.001
            ) {
                Task { await model.setVerticalShift(value) }
            }
        }
    }

    @ViewBuilder
    private var chapterOptions: some View {
        if model.chapters.isEmpty {
            Text("This file has no chapters.")
                .font(Theme.Font.playerRow)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                .padding(.top, Theme.Space.lg)
        } else {
            ForEach(Array(model.chapters.enumerated()), id: \.offset) { index, chapter in
                optionRow(
                    "\(PlayerModel.timecode(chapter.startSeconds))   \(chapter.name ?? "Chapter \(index + 1)")",
                    selected: model.currentChapter?.startSeconds == chapter.startSeconds
                ) {
                    Task { await model.jumpToChapter(chapter) }
                }
            }
        }
    }

    private var speedOptions: some View {
        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
            optionRow(
                speed == 1 ? "Normal" : String(format: "%.2f×", speed),
                selected: abs(model.playbackSpeed - speed) < 0.001
            ) {
                Task { await model.setPlaybackSpeed(speed) }
            }
        }
    }

    private var subtitleSizeOptions: some View {
        ForEach(SubtitleSize.allCases) { size in
            optionRow(size.title, selected: model.subtitleSize == size) {
                Task { await model.setSubtitleSize(size) }
            }
        }
    }

    /// The presets, here as well as in Settings, because choosing between looks is
    /// something you do against a frame rather than against a description of one.
    private var subtitleStyleOptions: some View {
        ForEach(SubtitleStyle.all) { style in
            optionRow(style.title, selected: model.subtitleStyle.id == style.id) {
                Task { await model.setSubtitleStyle(style) }
            }
        }
    }

    /// Offsets in tenths, out to a second either way.
    ///
    /// Subtitles arriving a beat after the speech is the complaint this answers,
    /// and the fix for it is a negative number — subtitles *earlier*. The list runs
    /// both ways because the opposite happens too on a track cut for a different
    /// release.
    private var subtitleDelayOptions: some View {
        ForEach([-1.0, -0.5, -0.3, -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.5, 1.0], id: \.self) { value in
            optionRow(
                value == 0 ? "In sync" : String(format: "%+.1f s", value),
                selected: abs(model.subtitleDelay - value) < 0.001
            ) {
                Task { await model.setSubtitleDelay(value) }
            }
        }
    }

    // Not private: the remaining option lists live in
    // PlayerSettingsPanel+Options.swift, and every one of them is built from this.
    func optionRow(
        _ title: String,
        detail: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PlayerPanelRow(title: title, detail: nil, subtitle: detail, selected: selected, action: action)
    }
}
