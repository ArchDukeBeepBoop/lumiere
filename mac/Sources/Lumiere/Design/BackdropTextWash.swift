import SwiftUI

/// A light darkening across the band where a backdrop's text sits, and nowhere else.
///
/// The full fades are gone — see the commit that removed them. What is left is the
/// smallest thing that keeps a white title readable over a photograph: no flat dim
/// over the whole picture, no dissolve into the page, and nothing at all above the
/// text. The top two thirds of every backdrop are untouched at full strength.
///
/// Black rather than the canvas colour, in both appearances, for the same reason
/// `Theme.Palette.onArtwork` is: this sits on a photograph, not on the page, and a
/// white wash in light mode would erase white text rather than support it.
///
/// One definition for all four backdrops — the home hero, the series and film
/// header, the collection header, the compact header — because four separately
/// tuned gradients is how they drifted apart the first time.
struct BackdropTextWash: View {

    /// Where the darkening starts, as a fraction of the backdrop's height.
    ///
    /// 0.62 leaves the top nearly two thirds clean. Text in all four surfaces sits
    /// in the bottom block, so anything earlier than this is dimming picture that no
    /// letter is ever drawn over.
    var start: CGFloat = 0.62

    /// How dark it gets at the very bottom.
    ///
    /// 0.5 against the old fades, which reached the canvas colour at full opacity —
    /// they replaced the artwork, this shades it. Enough for white text at title
    /// weight; not enough to grey out what is behind it.
    var strength: Double = 0.5

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: start),
                .init(color: .black.opacity(strength * 0.55), location: (start + 1) / 2),
                .init(color: .black.opacity(strength), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}
