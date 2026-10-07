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
            Divider()
            options
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        }
    }

    // MARK: - Left column

    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(Theme.Space.md)

            Text("Video")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.accent)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.sm)

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
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(disabled ? Theme.Palette.textDisabled : Theme.Palette.textPrimary)
                Text(currentValue(item))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(section == item ? Theme.Palette.surfaceRaised : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
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
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(Theme.Space.md)

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
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textMuted)
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
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.md)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
