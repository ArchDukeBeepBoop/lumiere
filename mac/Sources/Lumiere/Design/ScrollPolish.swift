import SwiftUI

/// The scrolling behaviour every long page in the app shares.
///
/// Two small things that are only noticeable when they are wrong.
///
/// `scrollBounceBehavior(.basedOnSize)` stops a page that fits on screen from
/// rubber-banding. A detail page for a film with no cast, a genre with four
/// titles, an empty library — all of them used to wobble under a trackpad as
/// though there were more below, which is the clearest possible signal that
/// there is content you have not reached, given at exactly the moment there is
/// none.
///
/// `scrollDismissesKeyboard` is not it; there is no keyboard here. What is here
/// is `scrollIndicators(.automatic)`, kept explicit so a future change to the
/// window's style cannot quietly turn the overlay scrollers into legacy ones and
/// take 15 points off every grid's width.
extension View {
    func polishedScrolling() -> some View {
        self
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
    }
}
