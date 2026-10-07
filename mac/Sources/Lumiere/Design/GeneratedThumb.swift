import SwiftUI
import LumiereKit

/// A stand-in 16:9 thumbnail, drawn locally, for items the server has no wide
/// artwork for at all.
///
/// The alternative was stretching a 2:3 poster to fill a 16:9 card, which is what
/// Continue Watching used to do: a 680px-wide poster forced across a 384pt (768px)
/// card is upscaled past its own resolution *and* cropped through the middle, which
/// is why those cards read as blurry. A drawn card is sharp at any size, says what
/// the thing is, and never pretends to be artwork it isn't.
///
/// The colour comes from a hash of the title, so a given show always gets the same
/// card rather than shuffling on every launch.
struct GeneratedThumb: View {
    let title: String
    let subtitle: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [base.opacity(0.85), base.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // A faint oversized glyph, so the card reads as "no artwork" rather than
            // as a flat colour swatch someone chose on purpose.
            Image(systemName: "play.tv")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Palette.onArtwork.opacity(0.18))

            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(title)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.onPlayerChrome)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.onPlayerChrome.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
        }
    }

    /// Deterministic hue from the title. `hashValue` is deliberately not used — it
    /// is seeded per process, so the same show would change colour between launches.
    private var base: Color {
        var hash: UInt64 = 5381
        for byte in title.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.45, brightness: 0.42)
    }
}
