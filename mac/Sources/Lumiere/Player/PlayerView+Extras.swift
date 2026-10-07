import SwiftUI
import LumiereKit

/// The menu bar's extra commands. See `PlaybackMenuController+Extras`.
extension PlayerView {
    func performExtra(_ command: PlayerCommand, _ model: PlayerModel) {
        switch command {
        case .episode(let forward):
            if let entry = forward ? model.nextEpisode : model.previousEpisode { play(entry) }
        case .nudgeSpeed(let delta): Task { await model.nudgeSpeed(delta) }
        case .toggleFlip(let horizontal): Task { await model.toggleFlip(horizontal: horizontal) }
        case .screenshot: Task { await model.saveScreenshot() }
        case .copyFrame: Task { await model.copyFrame() }
        case .nudgeAudioDelay(let direction):
            Task {
                if direction == 0 { await model.setAudioDelay(0) }
                else { await model.nudgeAudioDelay(direction) }
            }
        case .nudgeSubtitleDelay(let direction):
            Task {
                if direction == 0 { await model.setSubtitleDelay(0) }
                else { await model.nudgeSubtitleDelay(direction) }
            }
        case .addSubtitleFile(let url): Task { await model.addSubtitleFile(url) }
        case .setSubtitleSize(let size): Task { await model.setSubtitleSize(size) }
        case .startOver: Task { await model.startOver() }
        case .abLoop: Task { await model.stepABLoop() }
        case .sleep(let minutes): SleepTimer.set(minutes: minutes); model.say(SleepTimer.description)
        case .setAudioDevice(let device): Task { await model.setAudioDevice(device) }
        default: break
        }
    }
}
