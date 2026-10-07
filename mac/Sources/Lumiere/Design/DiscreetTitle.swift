import SwiftUI

extension View {
    /// A window title that names nothing while the private room is open.
    ///
    /// The window's title is what the Dock menu, Mission Control and the Window
    /// menu all show, and "Latest Adult" there says more than any cover does.
    func discreetNavigationTitle(_ title: String) -> some View {
        navigationTitle(RoomChrome.isOpen ? "Lumiere" : title)
    }
}
