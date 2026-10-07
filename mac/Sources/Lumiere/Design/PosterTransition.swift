import SwiftUI

/// The poster becomes the page.
///
/// Motion in this app has been functional — a hover lift, a fade — and nothing
/// more. Opening a title cross-faded to a detail page, which is the same
/// transition a settings pane gets, so the most characteristic act in a media
/// app felt like navigating a form.
///
/// What was wanted was SwiftUI's zoom transition, tying the poster you clicked
/// to the artwork that replaces it. `navigationTransition(.zoom(sourceID:in:))`
/// is iOS and tvOS only — it does not exist on macOS, and there is no AppKit
/// equivalent short of driving navigation through a custom overlay, which would
/// mean replacing a working navigation stack to buy an animation.
///
/// So this is the honest half: the destination *rises* into place rather than
/// cross-fading, which reads as the poster having opened even though the two
/// views are not geometrically linked.
///
/// The first attempt at this was a 1.5% scale — thirteen points of travel on a
/// nine-hundred-point page, layered under NavigationStack's own push, which is
/// to say invisible. It also used an inline spring in a codebase whose
/// `Theme.Motion` describes itself as short and springless, in the one file
/// whose entire subject is the design language's motion.
///
/// There is deliberately no source-side modifier. The first pass marked every
/// poster with `matchedTransitionSource`, on the theory that it cost nothing and
/// marked the seam. It is not free: it registers geometry tracking on every tile
/// in every shelf, a few hundred of them on the home screen, feeding a match
/// that can never happen on this platform — and it made scrolling stutter. A
/// hook for an API macOS does not have is not worth a frame.
struct PosterTransitionDestination: ViewModifier {

    /// Nil until the page has arrived, so the animation cannot re-fire.
    ///
    /// `.onAppear` alone fired again when the destination reappeared after a
    /// pop, so the page you came *back* to faded in as though it were new.
    @State private var hasArrived = false

    func body(content: Content) -> some View {
        content
            // Two small things rather than one large one: a lift and a fade.
            // Together they read as the page coming forward; a scale large
            // enough to notice on its own would be a page you have to wait for
            // before you can read it.
            .offset(y: hasArrived ? 0 : 14)
            .opacity(hasArrived ? 1 : 0)
            .animation(Theme.Motion.transition, value: hasArrived)
            .task {
                guard !hasArrived else { return }
                hasArrived = true
            }
            // Respected explicitly: the page must still arrive, it just arrives
            // already there.
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

extension View {

    /// Applied to a detail page as it is pushed.
    func posterTransitionDestination() -> some View {
        modifier(PosterTransitionDestination())
    }
}
