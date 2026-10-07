import SwiftUI
import LumiereKit

/// A library, as a piece of artwork you can click.
///
/// The point of the whole exercise: navigating to Anime, Movies or Hobby TV
/// used to require reading a column of words in the chrome, which is Jellyfin's
/// filing-cabinet model — you have to already know what you want before the UI
/// helps. Apple TV makes every destination a picture with a name on it, and this
/// is the library-shaped half of that; `GenreCard` is the other half.
///
/// Deliberately built to the same recipe as `GenreCard` — one image, a bottom
/// gradient, the name and a count, the shared hover lift — so the two rows read
/// as one family rather than as two people's work. The differences are only the
/// ones that carry meaning: portrait rather than 16:9, because a library is a
/// wall of posters, and a glyph rather than an initial in the fallback, because
/// "Music" and "My Videos" are kinds of thing where a genre is just a word.
///
/// One image per card, not a mosaic, and deliberately unlike `GenreCard` now
/// that it collages. Genres needed one because they share their newest titles
/// and the cards came out looking alike; libraries have no such problem — Anime
/// and Movies never draw the same poster — so a collage here would buy nothing
/// for the extra bitmaps in a row most people scroll past once.
struct LibraryCard: View {
    let item: LibraryCardItem
    let serverURL: URL
    let pipeline: ImagePipeline
    var width: CGFloat = Theme.Art.libraryCardWidth

    @State private var isHovering = false
    @Environment(\.displayScale) private var scale

    private var height: CGFloat { width / Theme.Art.posterAspect }

    /// The first title in the library that actually has artwork.
    ///
    /// Walked rather than taking the newest, because the newest thing in a library
    /// is very often the thing whose metadata has not been scraped yet, and that
    /// is precisely the card that would come out blank.
    private var request: ImageRequest? {
        for entry in item.artwork {
            if let request = ImageRequest.poster(
                for: entry, serverURL: serverURL, width: width, scale: scale
            ) {
                return request
            }
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            label
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.posterLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.posterLarge, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
        // The same lift every other card in the app takes, at the same numbers,
        // and with the shadow radius at zero when idle — a shadow left installed
        // at full radius gives every repeated tile an offscreen buffer.
        .shadow(
            color: isHovering ? Theme.Palette.cardShadow : .clear,
            radius: isHovering ? Theme.Elevation.hoverShadow : 0,
            y: isHovering ? Theme.Elevation.hoverShadowY : 0
        )
        .scaleEffect(isHovering ? Theme.Elevation.hoverScale : 1)
        .animation(Theme.Motion.hover, value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .labelledHelp("Open \(item.name)")
        // The card is one thing to a screen reader, not a picture next to two
        // strings — the artwork is decoration and the name is the control.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.subtitle)
    }

    @ViewBuilder
    private var background: some View {
        if let request {
            // Text is drawn on this. See `Theme.Palette.artworkPlaceholder`.
            RemoteImage(request: request, pipeline: pipeline, carriesText: true)
                .frame(width: width, height: height)
                .clipped()
                // Taller and heavier than the genre card's wash: the label sits over
                // a portrait poster, where the bottom third is as likely to be a
                // face or a title treatment as it is to be sky. Only over artwork —
                // laid over the drawn fallback below it would darken a light-mode
                // surface that already carries dark text.
                .overlay {
                    // Starts higher and lands darker than a scrim usually needs to.
                    //
                    // The art under a library card is a *poster*, and a poster
                    // carries its own title in its own bottom third — so "Movies"
                    // was landing on the word SPIDER-MAN and "Collections" on the
                    // word COLLECTION. Two titles fighting in one place reads as a
                    // rendering fault rather than a label. A scrim over an episode
                    // still can be subtle; this one cannot.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Theme.Palette.onArtwork, location: 0.42),
                            .init(color: Theme.Palette.onArtworkStrong, location: 0.68),
                            .init(color: Theme.Palette.onArtworkOpaque, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        } else {
            fallback
        }
    }

    /// The drawn card, for a library the cache has no artwork for — music and
    /// playlists always, and any library on the first run before the sync lands.
    ///
    /// The library's own glyph, set large and faint, rather than `GenreCard`'s
    /// giant initial: a row where Music, Movies and My Videos are three grey
    /// letters says less than one where they are a note, a strip of film and a
    /// camera, and the glyph is the same one the sidebar uses for that library.
    private var fallback: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Theme.Palette.surfaceRaised, Theme.Palette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: LibraryGlyph.name(for: item.library.collectionType))
                .font(.system(size: width * 0.62, weight: .regular))
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.10))
                .offset(x: width * 0.16, y: -width * 0.06)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(item.name)
                .font(Theme.Font.libraryTitle)
                .foregroundStyle(textColour)
                .tracking(-0.3)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
            Text(item.subtitle)
                .font(Theme.Font.caption)
                .foregroundStyle(mutedTextColour)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.bottom, Theme.Space.md)
    }

    /// White over a photograph, the page's own colour over the drawn fallback —
    /// white on the light-mode surface would be unreadable.
    private var textColour: Color {
        request == nil ? Theme.Palette.textPrimary : Theme.Palette.onArtworkText
    }
    private var mutedTextColour: Color {
        request == nil ? Theme.Palette.textMuted : Theme.Palette.onArtworkTextMuted
    }
}
