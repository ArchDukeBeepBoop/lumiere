import SwiftUI
import LumiereKit

/// The Continue banner: the franchise's key art across the row, "Continue
/// Monogatari" over it, and the next title to watch. A press opens that
/// title's page; the collection's name opens the collection.
struct ContinueFranchiseBanner: View {
    let banner: ContinueFranchise.Banner
    let serverURL: URL
    let pipeline: ImagePipeline
    @Environment(\.displayScale) private var scale
    @State private var isHovering = false

    private let height: CGFloat = 220

    var body: some View {
        NavigationLink(value: DetailRoute.forEntry(banner.next)) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(request: art, pipeline: pipeline, carriesText: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                LinearGradient(colors: [Theme.Palette.onArtworkOpaque, .clear],
                               startPoint: .leading, endPoint: .trailing)
                HStack(alignment: .bottom, spacing: Theme.Space.lg) {
                    RemoteImage(request: .poster(for: banner.next, serverURL: serverURL, width: 96, scale: scale),
                                pipeline: pipeline)
                        .frame(width: 96, height: 96 / Theme.Art.posterAspect)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous))
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Continue \(banner.collectionName)")
                            .font(Theme.Font.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.accentOnArtwork)
                        Text(banner.next.item.name)
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.onArtworkText)
                            .lineLimit(2)
                        Text(detail)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.onArtworkTextMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Space.xl)
            }
            .frame(height: height)
            .background(Theme.Palette.artworkPlaceholder)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .scaleEffect(isHovering ? 1.01 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .contextMenu {
            if let collection = banner.collection {
                NavigationLink("Open \(banner.collectionName)", value: DetailRoute.forEntry(collection))
            }
        }
        .padding(.horizontal, Theme.Space.shelfInset)
        .accessibilityLabel("Continue \(banner.collectionName): \(banner.next.item.name), \(detail)")
    }

    /// The collection's key art, else the next title's own backdrop.
    private var art: ImageRequest? {
        if let collection = banner.collection, let tag = collection.item.backdropTag {
            return ImageRequest(serverURL: serverURL, itemId: collection.id, kind: .backdrop, tag: tag,
                                displayWidth: 1200, aspectRatio: 16 / 9, screenScale: scale)
        }
        return .backdrop(for: banner.next, serverURL: serverURL, width: 1200, scale: scale)
    }

    private var detail: String {
        var parts = ["Next to watch"]
        if let year = banner.next.item.productionYear { parts.append(String(year)) }
        parts.append(banner.next.item.itemType == .series ? "Show" : "Film")
        return parts.joined(separator: " · ")
    }
}
