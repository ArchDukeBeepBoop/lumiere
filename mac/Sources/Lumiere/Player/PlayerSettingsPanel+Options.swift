import SwiftUI
import LumierePlayer

/// The right-hand column's remaining option lists.
///
/// Split from PlayerSettingsPanel.swift for the project's 300-line rule. Each is
/// the same shape — a fixed set of values, one row each, the current one ticked —
/// which is what keeps the panel readable as one thing rather than seven controls.
extension PlayerSettingsPanel {

    var upscalingOptions: some View {
        ForEach(UpscalingMode.allCases) { mode in
            optionRow(mode.title, detail: mode.explanation, selected: model.upscaling == mode) {
                Task { await model.setUpscaling(mode) }
            }
        }
    }

    /// Repeat, as QuickTime's View ▸ Loop does it.
    ///
    /// Per file and per session: it is turned off again when anything new
    /// loads, because a player that silently repeats the *next* thing you open
    /// is one that will not stop and does not say why.
    /// Two switches rather than four combinations: mirroring left-to-right
    /// and top-to-bottom are separate facts about a file, and each is undone
    /// on its own.
    var flipOptions: some View {
        Group {
            optionRow(
                "Horizontal",
                detail: "Mirror left to right.",
                selected: model.flipHorizontal
            ) {
                Task { await model.setFlip(horizontal: !model.flipHorizontal, vertical: model.flipVertical) }
            }
            optionRow(
                "Vertical",
                detail: "Mirror top to bottom.",
                selected: model.flipVertical
            ) {
                Task { await model.setFlip(horizontal: model.flipHorizontal, vertical: !model.flipVertical) }
            }
        }
    }

    var loopOptions: some View {
        Group {
            optionRow("Off", selected: !model.isLooping) {
                if model.isLooping { Task { await model.toggleLooping() } }
            }
            optionRow(
                "On",
                detail: "Repeats this file instead of ending it. The next episode is not queued.",
                selected: model.isLooping
            ) {
                if !model.isLooping { Task { await model.toggleLooping() } }
            }
        }
    }

    var ambientOptions: some View {
        Group {
            optionRow("Off", selected: !model.ambientMode) { model.ambientMode = false }
            optionRow(
                "On",
                detail: "Dims everything around the picture, so a lit room doesn't fight the film.",
                selected: model.ambientMode
            ) {
                model.ambientMode = true
            }
        }
    }

    var statisticsOptions: some View {
        Group {
            optionRow("Off", selected: !model.showsStatisticsHUD) {
                model.showsStatisticsHUD = false
            }
            optionRow(
                "On",
                detail: "Shows the decode path, dropped frames and bitrate over the picture.",
                selected: model.showsStatisticsHUD
            ) {
                model.showsStatisticsHUD = true
            }
        }
    }
}
