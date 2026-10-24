import SwiftUI
import LumiereKit

/// Subtitles: timing first, because a line out of sync is the reason most
/// people open this; then how the text looks and where it sits.
struct PlayerSidebarSubtitles: View {
    let model: PlayerModel
    @State private var exactSize = false
    @State private var batch: (episodes: [LibraryEntry], files: [URL])?

    var body: some View {
        if !(model.engineRef?.supportsSubtitleDelay ?? false) {
            unavailable
        } else {
            PlayerGroup(title: "Timing",
                        footnote: "Wait for a line to be spoken, then press Next Line Now — the subtitles move to meet it.") {
                PlayerSliderRow(
                    icon: "clock.arrow.2.circlepath", title: "Delay",
                    value: model.subtitleDelay, range: -10...10, step: 0.1,
                    format: SidebarFormat.seconds,
                    onChange: { value in Task { await model.setSubtitleDelay(value) } }
                )
                HStack(spacing: Theme.Space.xs) {
                    Button { Task { await model.syncSubtitleLine(-1) } } label: {
                        Label("Last Line Again", systemImage: "backward.end")
                    }
                    Button { Task { await model.syncSubtitleLine(1) } } label: {
                        Label("Next Line Now", systemImage: "forward.end")
                    }
                }
                .font(Theme.Font.playerRow.weight(.medium))
                .buttonStyle(PlayerCapsuleButtonStyle(prominent: false))
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, 4)
            }

            PlayerGroup(title: "Files",
                        footnote: "Pick a folder of subtitles once; each episode gets its own, matched by number.") {
                PlayerActionRow(icon: "captions.bubble", title: "Add Subtitles to This Season…") {
                    Task {
                        let files = model.chooseSubtitleFiles()
                        guard !files.isEmpty else { return }
                        batch = (await model.subtitleScope(), files)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { batch != nil }, set: { if !$0 { batch = nil } })) {
                if let batch {
                    SubtitleFolderSheet(episodes: batch.episodes, files: batch.files) { links in
                        Task { await model.applySubtitleLinks(links) }
                    }
                }
            }

            PlayerGroup(title: "Look") {
                ForEach(SubtitleStyle.all) { style in
                    PlayerPanelRow(title: style.title, detail: nil,
                                   selected: model.subtitleStyle.id == style.id) {
                        Task { await model.setSubtitleStyle(style) }
                    }
                }
            }

            PlayerGroup(title: "Size") {
                PlayerSegmented(items: SizeMode.allCases, selection: Binding(
                    get: { exactSize ? .exact : .named },
                    set: { mode in
                        exactSize = mode == .exact
                        Task { await model.setSubtitleScale(exactSize ? (model.subtitleScale ?? 1) : nil) }
                    }
                ), title: \.title)
                .padding(Theme.Space.xs)
                if exactSize {
                    PlayerSliderRow(
                        icon: "textformat.size", title: "Scale",
                        value: (model.subtitleScale ?? 1) * 100, range: 30...300, step: 5, neutral: 100,
                        format: SidebarFormat.percent,
                        onChange: { value in Task { await model.setSubtitleScale(value / 100) } }
                    )
                } else {
                    ForEach(SubtitleSize.allCases) { size in
                        PlayerPanelRow(title: size.title, detail: nil, selected: model.subtitleSize == size) {
                            Task { await model.setSubtitleSize(size) }
                        }
                    }
                }
            }

            PlayerGroup(title: "Position") {
                PlayerSliderRow(
                    icon: "arrow.up.and.down.text.horizontal", title: "Height",
                    value: Double(model.subtitlePosition), range: 50...100, step: 1, neutral: 100,
                    format: { $0 >= 99.5 ? "Bottom" : "\(Int(100 - $0))% up" },
                    onChange: { value in Task { await model.setSubtitlePosition(Int(value)) } }
                )
            }
        }
    }

    private var unavailable: some View {
        Text("This file plays on the system player, which draws subtitles its own way. Timing, look and position are available for files mpv plays.")
            .font(Theme.Font.playerRow)
            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
            .padding(Theme.Space.sm)
    }

    enum SizeMode: String, CaseIterable, Identifiable {
        case named, exact
        var id: String { rawValue }
        var title: String { self == .named ? "Small · Normal · Large" : "Exact" }
    }
}
