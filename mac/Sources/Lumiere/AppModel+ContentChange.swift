import Foundation
import LumiereKit

/// Telling the home screen that what it is showing has changed.
///
/// The third time this has been reported, and the first two fixes were both in the
/// wrong place. Each surface that wrote something re-read its own shelves, so every
/// new command and every new screen had to remember to do it — and most did not.
/// Closing the player did not, which is the one that matters most: watching an
/// episode is the commonest way to change what belongs on the home screen, and
/// Continue Watching sat unmoved until you navigated away and came back.
///
/// So it lives with the *write* instead. Anything that changes an item's watch
/// state, its metadata, its artwork or whether it belongs on a shelf calls this, and
/// every surface that triggers such a write inherits the refresh whether or not
/// whoever added it thought about the home screen.
///
/// Cheap enough to call freely: `HomeModel.refresh` is a no-op before the first load
/// and its queries are local reads against a cache that is already warm.
@MainActor
extension AppModel {

    /// Something about an item changed. Re-read the shelves.
    func contentDidChange(_ reason: String = "content changed") async {
        await homeModel?.refresh(reason)
    }

    /// The same, for callers that cannot await — a SwiftUI action closure, a
    /// completion handler.
    func noteContentChanged(_ reason: String = "content changed") {
        Task { @MainActor in await contentDidChange(reason) }
    }
}
