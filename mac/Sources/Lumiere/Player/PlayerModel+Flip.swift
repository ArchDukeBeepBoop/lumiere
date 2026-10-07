import Foundation
import LumiereKit

/// Carrying a show's flip from one episode to the next. See `FlipMemory`.
@MainActor
extension PlayerModel {

    /// The show this file belongs to, or the file itself for a film.
    private func flipTitleId() async -> String {
        (try? await repository.entry(id: itemId))?.item.seriesId ?? itemId
    }

    /// Applies the flip remembered for this show, if the owner keeps one.
    func restoreFlip() async {
        guard Preference.remembersFlip.value else { return }
        let flip = FlipMemory.flip(for: await flipTitleId())
        guard flip.horizontal || flip.vertical else { return }
        flipHorizontal = flip.horizontal
        flipVertical = flip.vertical
        await engineRef?.setFlip(horizontal: flip.horizontal, vertical: flip.vertical)
    }

    func rememberFlip() async {
        guard Preference.remembersFlip.value else { return }
        FlipMemory.remember(
            horizontal: flipHorizontal, vertical: flipVertical, for: await flipTitleId()
        )
    }
}
