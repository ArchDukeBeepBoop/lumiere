import Foundation
import CoreGraphics

public struct ImageRequest: Sendable, Hashable {
    public let serverURL: URL
    public let itemId: String
    public let kind: JellyfinImageURL.ImageKind
    public let tag: String?

    /// Set for images that are not item artwork — trickplay sheets, for one —
    /// where the URL is known outright rather than derived from an item and tag.
    private let explicitURL: URL?
    private let explicitKey: String?
    /// Points, not pixels. The pipeline applies the screen scale.
    public let displayWidth: CGFloat
    public let aspectRatio: CGFloat
    public let screenScale: CGFloat

    public init(
        serverURL: URL,
        itemId: String,
        kind: JellyfinImageURL.ImageKind,
        tag: String?,
        displayWidth: CGFloat,
        aspectRatio: CGFloat,
        screenScale: CGFloat = 2
    ) {
        self.serverURL = serverURL
        self.itemId = itemId
        self.kind = kind
        self.tag = tag
        self.displayWidth = displayWidth
        self.aspectRatio = aspectRatio
        self.screenScale = screenScale
        self.explicitURL = nil
        self.explicitKey = nil
    }

    /// A request for an image at a known URL.
    ///
    /// Goes through the same bounded caches as artwork, which is the point: a
    /// long scrub through trickplay sheets must evict like everything else
    /// rather than growing without limit.
    public init(
        explicitURL: URL,
        cacheKey: String,
        displayWidth: CGFloat,
        aspectRatio: CGFloat,
        screenScale: CGFloat = 2
    ) {
        self.serverURL = explicitURL
        self.itemId = cacheKey
        self.kind = .primary
        self.tag = nil
        self.displayWidth = displayWidth
        self.aspectRatio = aspectRatio
        self.screenScale = screenScale
        self.explicitURL = explicitURL
        self.explicitKey = cacheKey
    }

    /// The width asked of the server, quantised to the ladder and capped by kind.
    ///
    /// The cap is the same one `decodePixelSize` applies, and it belongs here too.
    /// A backdrop drawn across a 1512pt window at 2x laddered to 3840, so the app
    /// downloaded a 3840-pixel image in order to decode it to 2560 and throw the
    /// rest away — and, worse for offline, the disk key moved with the window: the
    /// same backdrop at 1200pt and at 1512pt were two different downloads, so
    /// nothing warmed in advance could reliably be hit later.
    public var requestWidth: Int {
        min(
            Downsample.requestWidth(forDisplayWidth: displayWidth, screenScale: screenScale),
            Self.decodeCeiling(for: kind)
        )
    }

    /// The longest edge this image is decoded to, quantised, and capped for the
    /// kinds that are drawn full-bleed.
    ///
    /// Two problems, one property.
    ///
    /// **The cap.** Backdrops are requested at the window's own width, and the only
    /// ceiling was 4096. At a 1680pt window that decodes 3360x1890 — 24.2 MB and
    /// ~600 ms for a single image, against 922 KB for a shelf poster. One hero was
    /// worth twenty-six posters and evicted about three shelves out of the 96 MB
    /// cache every time it was drawn. 2560 costs 14.1 MB and looks the same behind
    /// `BackdropTextWash` at any window this app runs in.
    ///
    /// **The quantisation.** `decodePixelSize` feeds `cacheKey`, and the backdrop
    /// sites pass `geometry.size.width` unrounded — so every pixel width touched
    /// during a live window resize was a distinct cache key, a distinct decode, and
    /// a distinct 14–24 MB insertion, none of them cancellable. Rounding up to a
    /// 256-pixel step turns a 1200→2000pt drag into four decodes instead of eight
    /// hundred, and makes re-widening to a size already visited a cache hit. The
    /// disk layer already had a ladder; only the decode did not.
    public var decodePixelSize: Int {
        let raw = Downsample.targetPixelSize(
            displayWidth: displayWidth,
            aspectRatio: aspectRatio,
            screenScale: screenScale,
            maximum: Self.decodeCeiling(for: kind)
        )
        let step = 256
        return min(
            ((raw + step - 1) / step) * step,
            Self.decodeCeiling(for: kind)
        )
    }

    /// How large a decode any one kind is allowed to be.
    ///
    /// Full-bleed art is capped; everything else keeps the old 4096, which it never
    /// approaches — a poster at the largest tile the grid offers is 440 pixels.
    static func decodeCeiling(for kind: JellyfinImageURL.ImageKind) -> Int {
        switch kind {
        case .backdrop, .thumb: return 2560
        default: return 4096
        }
    }

    public var cacheKey: String {
        if let explicitKey { return "\(explicitKey)|\(decodePixelSize)" }
        return JellyfinImageURL.cacheKey(
            itemId: itemId, kind: kind, tag: tag, maxWidth: decodePixelSize
        )
    }

    /// The disk cache stores what the server sent, so its key is keyed by the
    /// *requested* width, not the decode size. Several cell sizes can share one
    /// downloaded file.
    public var diskKey: String {
        if let explicitKey { return explicitKey }
        return JellyfinImageURL.cacheKey(
            itemId: itemId, kind: kind, tag: tag, maxWidth: requestWidth
        )
    }

    public var url: URL? {
        if let explicitURL { return explicitURL }
        return JellyfinImageURL.url(
            serverURL: serverURL, itemId: itemId, kind: kind, tag: tag, maxWidth: requestWidth
        )
    }
}
