import SwiftUI
import LumiereKit

/// A cover in a private library, blurred until the pointer is on it.
///
/// Discreet art already kept frames out of Continue Watching. The grids and
/// shelves still drew every cover sharp, which is what someone glancing at the
/// screen sees first. Held back, a wall of them is a wall of colour; pointing
/// at one shows it. A setting, on by default.
struct CoverHoldBack: ViewModifier {
    let libraryId: String?
    let isHovering: Bool
    @Environment(\.privateLibraryIds) private var privateIds
    @AppStorage(Preference.roomBlursCovers.name) private var blurs = Preference.roomBlursCovers.defaultValue

    func body(content: Content) -> some View {
        let held = blurs && !isHovering && libraryId.map(privateIds.contains) == true
        content
            .blur(radius: held ? 16 : 0, opaque: true)
            .animation(Theme.Motion.hover, value: held)
    }
}

extension View {
    func coverHeldBack(libraryId: String?, isHovering: Bool) -> some View {
        modifier(CoverHoldBack(libraryId: libraryId, isHovering: isHovering))
    }
}
