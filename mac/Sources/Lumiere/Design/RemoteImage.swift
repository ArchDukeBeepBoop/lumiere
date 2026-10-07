import SwiftUI
import LumiereKit

/// Draws artwork from the pipeline, at exactly the size it occupies.
///
/// `.task(id:)` is doing the load *and* the cancellation: SwiftUI cancels it when
/// the view leaves the hierarchy or the request changes, so scrolling quickly
/// past a hundred posters abandons those downloads instead of finishing them all.
/// That is the difference between a grid that settles at 90 MB and one that
/// climbs while you scroll.
struct RemoteImage: View {
    let request: ImageRequest?
    let pipeline: ImagePipeline
    var contentMode: ContentMode = .fill
    /// Whether text is drawn on top of this image.
    ///
    /// Sets the ground a missing picture leaves behind. See
    /// `Theme.Palette.artworkPlaceholder`.
    var carriesText = false

    @State private var decoded: DecodedImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let decoded {
                Image(decoded.cgImage, scale: request?.screenScale ?? 2, label: Text(""))
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .animation(Theme.Motion.hover, value: decoded == nil)
        .onDisappear {
            // Let the bitmap go when the cell scrolls away.
            //
            // Cancelling the *load* was never the whole story: a cell that had
            // already finished held its decoded CGImage in @State for as long as
            // SwiftUI kept the view, and a lazy stack keeps them well past the
            // viewport. Scrolling a home screen of eleven shelves to the bottom
            // therefore ended with every poster it had ever drawn still resident —
            // measured at 395 MB against 177 MB at rest.
            //
            // Cheap to undo: the pipeline's memory cache still has it, so coming
            // back is a dictionary lookup rather than a download and a decode.
            decoded = nil
        }
        .task(id: request) {
            decoded = nil
            didFail = false
            guard let request else { return }

            // Retried, with a widening pause. A single failure used to be permanent
            // for the whole session: the load runs once per `.task(id:)`, so a
            // request that lost out while the server was busy syncing left a blank
            // card until the view was rebuilt. On a real library mid-sync that was
            // most of the grid.
            //
            // Three attempts and then it gives up for good — a genuinely missing
            // image must not turn into an endless retry loop behind every cell.
            // Two attempts, not three, and a short pause. The three-attempt version
            // I added to fix blank posters also made every *permanently* missing image
            // cost 1.2 seconds and three round trips — and a library has plenty of
            // those, since 107 series here have no poster on the server at all. On a
            // scrolling grid that is a lot of work spent re-asking for nothing.
            //
            // One retry recovers the case this exists for, a request that lost out
            // while the server was busy, at a third of the cost.
            for attempt in 1...2 {
                let result = await pipeline.image(for: request)
                guard !Task.isCancelled else { return }
                if let result {
                    decoded = result
                    didFail = false
                    return
                }
                guard attempt < 2 else { break }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            didFail = true
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(carriesText ? Theme.Palette.artworkPlaceholder : Theme.Palette.surface)
            .overlay {
                if didFail || request == nil {
                    Image(systemName: "film")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Palette.textDisabled)
                }
            }
    }
}

extension ImageRequest {
    /// Builds a request for an item's poster, following the series fallback.
    ///
    /// An episode in a poster-shaped cell always gets the show's poster. Its own
    /// Primary image is a 16:9 frame still, and cropping one to 2:3 gives the
    /// sliver-of-a-scene that made these shelves look broken.
    ///
    /// This used to be an opt-in flag. There is no cell where the opposite is the
    /// better answer, so it only ever had one correct setting — and four call sites
    /// passed it while eight did not, which is precisely the inconsistency that got
    /// reported. A parameter with one right value is a bug waiting for the next call
    /// site, so it is gone.
    static func poster(
        for entry: LibraryEntry,
        serverURL: URL,
        width: CGFloat,
        scale: CGFloat
    ) -> ImageRequest? {
        let item = entry.item

        // Episodes only. A *season's* own Primary image is already a portrait poster
        // — often the one that distinguishes it from the rest of the show — so a
        // season cell keeps it and falls through below.
        if item.itemType == .episode,
           let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return ImageRequest(
                serverURL: serverURL, itemId: seriesId, kind: .primary, tag: tag,
                displayWidth: width, aspectRatio: Theme.Art.posterAspect, screenScale: scale
            )
        }

        if let tag = item.primaryTag {
            return ImageRequest(
                serverURL: serverURL, itemId: item.id, kind: .primary, tag: tag,
                displayWidth: width, aspectRatio: Theme.Art.posterAspect, screenScale: scale
            )
        }
        if let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return ImageRequest(
                serverURL: serverURL, itemId: seriesId, kind: .primary, tag: tag,
                displayWidth: width, aspectRatio: Theme.Art.posterAspect, screenScale: scale
            )
        }
        // Nothing shaped like a poster exists for this item, but Jellyfin may have
        // already scraped a backdrop or thumb for it — common for anime, where a
        // provider often has a landscape image and no cover art. A cropped backdrop
        // beats a blank placeholder, and it costs no extra request: these tags are
        // already in the synced row.
        if let tag = item.backdropTag {
            return ImageRequest(
                serverURL: serverURL, itemId: item.id, kind: .backdrop, tag: tag,
                displayWidth: width, aspectRatio: Theme.Art.posterAspect, screenScale: scale
            )
        }
        if let tag = item.thumbTag {
            return ImageRequest(
                serverURL: serverURL, itemId: item.id, kind: .thumb, tag: tag,
                displayWidth: width, aspectRatio: Theme.Art.posterAspect, screenScale: scale
            )
        }
        return nil
    }

    /// Builds a request for an item's wide image, preferring its own artwork over
    /// the parent's so an episode shows its own still.
    static func backdrop(
        for entry: LibraryEntry,
        serverURL: URL,
        width: CGFloat,
        scale: CGFloat,
        preferSeriesThumb: Bool = false,
        unifiesEpisodeArt: Bool = false,
        /// Whether this item's `Primary` is a frame grab rather than a poster. True
        /// for files in a folder library. See `FolderLibraries`.
        primaryIsWide: Bool = false,
        /// Show artwork only — never a frame from the episode. The show's
        /// backdrop, else its poster, else nothing. See `DiscreetArtPolicy`.
        showArtOnly: Bool = false
    ) -> ImageRequest? {
        let item = entry.item

        if showArtOnly {
            // The poster is accepted here despite the note below about forcing
            // a 2:3 image into a 16:9 card. A soft crop of the show's poster is
            // the right picture for these libraries; a sharp frame from the
            // episode is the wrong one at any resolution.
            let seriesPoster = (
                item.seriesId ?? "", JellyfinImageURL.ImageKind.primary, item.seriesPrimaryImageTag
            )
            let showArt = [
                (item.parentBackdropItemId ?? "", JellyfinImageURL.ImageKind.backdrop, item.parentBackdropTag),
                seriesPoster,
            ]
            for (id, kind, tag) in showArt where tag != nil && !id.isEmpty {
                return ImageRequest(
                    serverURL: serverURL, itemId: id, kind: kind, tag: tag,
                    displayWidth: width, aspectRatio: Theme.Art.backdropAspect, screenScale: scale
                )
            }
            return nil
        }

        // A 16:9 card wants genuinely wide artwork. `preferSeriesThumb` only reorders
        // which wide image is tried first: the show's own backdrop, so a shelf reads
        // as one shelf rather than a set of unrelated frame grabs, before falling back
        // to this episode's own still.
        //
        // What it deliberately no longer does is reach for the series *poster*. A 2:3
        // poster forced to fill a 384pt-wide 16:9 card is upscaled past its own width
        // and cropped through the middle — sharp source, blurry result — which is what
        // "the thumbs are low resolution" actually was. When no wide image exists at
        // all, `GeneratedThumb` draws a card instead, which stays crisp at any size.
        var candidates: [(String, JellyfinImageURL.ImageKind, String?)] = []
        let parentBackdrop = (item.parentBackdropItemId ?? "", JellyfinImageURL.ImageKind.backdrop, item.parentBackdropTag)
        if preferSeriesThumb { candidates.append(parentBackdrop) }
        candidates += [
            (item.id, .backdrop, item.backdropTag),
            (item.id, .thumb, item.thumbTag),
        ]
        // `unifiesEpisodeArt` puts the show's backdrop above an episode's *Primary*,
        // which gives a season one picture instead of twelve.
        //
        // Off by default, and that default is the correction: it shipped as the only
        // behaviour, and a library whose provider *does* have per-episode stills lost
        // them — an episode's own frame is the better picture whenever it is a real
        // one, and defaulting to the show's art throws that away everywhere to fix
        // the libraries where it does not exist. On those, a Primary is whatever the
        // scraper attached, which is the same image on every episode, and the show's
        // backdrop is at least true of all of them. That is a taste call about a
        // particular library, so it is a switch.
        //
        // A genuine still — a Backdrop or a Thumb — wins above either way.
        //
        // `primaryIsWide` is the same exception for a different reason: a loose file
        // in a folder library has no scraped poster either, so its Primary is also a
        // still off the video.
        let episodePrimary = (
            item.id, JellyfinImageURL.ImageKind.primary,
            // Extras and loose videos too: nothing scrapes a poster for a
            // featurette or an opening, so their Primary is always a frame of
            // the video — and leaving it out drew every extra as the show's
            // backdrop, or as a blank card where the show had none.
            (item.itemType == .episode || item.itemType == .video || item.extraType != nil
             || primaryIsWide) ? item.primaryTag : nil
        )
        if unifiesEpisodeArt {
            if !preferSeriesThumb { candidates.append(parentBackdrop) }
            candidates.append(episodePrimary)
        } else {
            candidates.append(episodePrimary)
            if !preferSeriesThumb { candidates.append(parentBackdrop) }
        }

        for (id, kind, tag) in candidates where tag != nil && !id.isEmpty {
            return ImageRequest(
                serverURL: serverURL, itemId: id, kind: kind, tag: tag,
                displayWidth: width, aspectRatio: Theme.Art.backdropAspect, screenScale: scale
            )
        }
        return nil
    }

    static func logo(
        for entry: LibraryEntry,
        serverURL: URL,
        width: CGFloat,
        scale: CGFloat
    ) -> ImageRequest? {
        guard let tag = entry.item.logoTag else { return nil }
        return ImageRequest(
            serverURL: serverURL, itemId: entry.item.id, kind: .logo, tag: tag,
            displayWidth: width, aspectRatio: 2.5, screenScale: scale
        )
    }
}
