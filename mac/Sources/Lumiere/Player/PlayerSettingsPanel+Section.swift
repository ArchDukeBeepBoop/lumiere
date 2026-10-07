import SwiftUI

/// What the settings panel's left column lists.
///
/// Split from PlayerSettingsPanel.swift for the project's 300-line rule. An
/// extension rather than a free enum so it stays `PlayerSettingsPanel.Section`
/// at every call site.
extension PlayerSettingsPanel {

    enum Section: String, CaseIterable, Identifiable {
        case aspectRatio, verticalShift, flip, chapters, playbackSpeed, loop
        case subtitleStyle, subtitleSize, subtitleDelay, upscaling, ambientMode, statistics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aspectRatio: return "Aspect Ratio"
            case .verticalShift: return "Vertical Shift"
            case .flip: return "Flip"
            case .chapters: return "Chapters"
            case .playbackSpeed: return "Playback Speed"
            case .loop: return "Loop"
            case .subtitleStyle: return "Subtitle Style"
            case .subtitleSize: return "Subtitle Size"
            case .subtitleDelay: return "Subtitle Delay"
            case .upscaling: return "Upscaling"
            case .ambientMode: return "Ambient Mode"
            case .statistics: return "Playback Stats (HUD)"
            }
        }

        /// Only mpv can honour geometry and scaler changes.
        var needsVideoAdjustments: Bool {
            switch self {
            case .aspectRatio, .verticalShift, .flip, .upscaling: return true
            // Not a geometry change, but the same story: only mpv can do it.
            case .subtitleDelay, .subtitleSize, .subtitleStyle: return true
            default: return false
            }
        }
    }
}
