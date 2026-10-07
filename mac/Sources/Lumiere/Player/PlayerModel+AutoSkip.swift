import Foundation
import LumiereKit

/// The player's half of `AutoSkip`.
@MainActor
extension PlayerModel {

    /// Intros skipped automatically in this session, so each is skipped once
    /// and scrubbing back into one after an undo is respected.
    private static var autoSkipped: Set<String> = []

    /// Called on every position tick. Cheap when there is nothing to do.
    func autoSkipIfDue() {
        guard Preference.autoSkipsIntros.value, let key = introSeriesId,
              AutoSkip.isOn(for: key) else { return }
        for prompt in activePrompts {
            guard case .skip(let label, let target) = prompt, label == "Skip Intro" else { continue }
            let mark = "\(itemId)|\(Int(target))"
            guard !Self.autoSkipped.contains(mark) else { return }
            Self.autoSkipped.insert(mark)
            Task { await skip(to: target, label: label, automatic: true) }
            return
        }
    }
}
