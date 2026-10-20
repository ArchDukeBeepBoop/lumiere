import SwiftUI
import LumiereKit

extension PlayerView {
    /// Your queue first, then the season. See `PlayQueue`.
    func playNextEpisode(_ model: PlayerModel) {
        if let queued = PlayQueue.shared.takeNext(after: model.itemId) { play(queued); return }
        guard let next = model.nextEpisode else { return }
        play(next)
    }

}
