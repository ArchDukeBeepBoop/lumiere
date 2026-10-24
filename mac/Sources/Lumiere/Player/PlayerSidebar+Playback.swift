import SwiftUI
import LumiereKit

/// Playback: speed, repeats, the sleep timer, stepping, and the places worth
/// going back to — bookmarks you made beside the chapters the file came with.
struct PlayerSidebarPlayback: View {
    let model: PlayerModel
    @State private var sleep = SleepTimer.description
    @State private var renaming: Bookmark?
    @State private var newLabel = ""

    var body: some View {
        PlayerGroup(title: "Speed") {
            PlayerSliderRow(
                icon: "gauge.with.dots.needle.67percent", title: "Speed",
                value: model.playbackSpeed, range: 0.25...3, step: 0.05, neutral: 1,
                format: { abs($0 - 1) < 0.01 ? "Normal" : String(format: "%.2f×", $0) },
                onChange: { value in Task { await model.setPlaybackSpeed(value) } }
            )
        }

        PlayerGroup(title: "Repeat") {
            PlayerSwitchRow(icon: "repeat", title: "Loop This File", isOn: Binding(
                get: { model.isLooping }, set: { _ in Task { await model.toggleLooping() } }))
            PlayerActionRow(icon: "repeat.1", title: "A–B Loop", detail: abDetail, trailing: abTrailing) {
                Task { await model.stepABLoop() }
            }
        }

        PlayerGroup(title: "Sleep Timer") {
            ForEach([(0, "After This Episode"), (15, "In 15 Minutes"), (30, "In 30 Minutes"),
                     (60, "In an Hour"), (-1, "Off")], id: \.0) { minutes, title in
                PlayerPanelRow(title: title, detail: nil, selected: isSleep(minutes)) {
                    SleepTimer.set(minutes: minutes)
                    sleep = SleepTimer.description
                    model.say(sleep)
                }
            }
        }

        PlayerGroup(title: "Frame by Frame", footnote: "Pauses, then moves one picture at a time. Also , and . on the keyboard.") {
            HStack(spacing: Theme.Space.xs) {
                Button { Task { await model.stepFrame(-1) } } label: { Label("Back", systemImage: "backward.frame") }
                Button { Task { await model.stepFrame(1) } } label: { Label("Forward", systemImage: "forward.frame") }
                Button { Task { await model.saveScreenshot() } } label: { Label("Still", systemImage: "camera") }
            }
            .font(Theme.Font.playerRow.weight(.medium))
            .buttonStyle(PlayerCapsuleButtonStyle(prominent: false))
            .padding(Theme.Space.xs)
        }

        PlayerGroup(title: "Bookmarks", footnote: "⌘B marks the moment on screen. Right-click one to rename or remove it.") {
            PlayerActionRow(icon: "bookmark", title: "Add Bookmark", trailing: PlayerModel.timecode(model.position)) {
                model.addBookmark()
            }
            ForEach(model.bookmarks) { mark in
                PlayerPanelRow(title: mark.label, detail: PlayerModel.timecode(mark.seconds), selected: false) {
                    Task { await model.seek(to: mark.seconds) }
                }
                .contextMenu {
                    Button("Rename…") { renaming = mark; newLabel = mark.label }
                    Button("Remove", role: .destructive) { model.removeBookmark(mark) }
                }
            }
        }
        .alert("Rename Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newLabel)
            Button("Rename") { if let mark = renaming { model.renameBookmark(mark, to: newLabel) } }
            Button("Cancel", role: .cancel) {}
        }

        if !model.chapters.isEmpty {
            PlayerGroup(title: "Chapters") {
                ForEach(Array(model.chapters.enumerated()), id: \.offset) { index, chapter in
                    PlayerPanelRow(title: chapter.name ?? "Chapter \(index + 1)",
                                   detail: PlayerModel.timecode(chapter.startSeconds),
                                   selected: model.currentChapter?.startSeconds == chapter.startSeconds) {
                        Task { await model.jumpToChapter(chapter) }
                    }
                }
            }
        }

        PlayerGroup(title: "Information") {
            PlayerSwitchRow(icon: "chart.bar.xaxis", title: "Playback Stats",
                            detail: "Decoder, dropped frames and bitrate over the picture.",
                            isOn: Binding(get: { model.showsStatisticsHUD }, set: { model.showsStatisticsHUD = $0 }))
        }
    }

    private func isSleep(_ minutes: Int) -> Bool {
        switch (SleepTimer.mode, minutes) {
        case (.off, -1), (.afterEpisode, 0): return true
        default: return false
        }
    }

    private var abDetail: String {
        switch model.abLoop {
        case (nil, _): return "Press to mark where the loop starts."
        case (_, nil): return "Press again where it should end."
        default: return "Playing between the marks. Press to clear."
        }
    }

    private var abTrailing: String? {
        guard let a = model.abLoop.a else { return nil }
        let start = PlayerModel.timecode(a)
        return model.abLoop.b.map { "\(start)–\(PlayerModel.timecode($0))" } ?? start
    }
}
