import SwiftUI
import QuickLookThumbnailing

/// A still for a file on the Recent list, from Quick Look — the same
/// thumbnails Finder shows: a frame for the formats macOS reads (MP4, MOV,
/// M4V…), cover art for music. A file it cannot read (most MKV) keeps its icon.
///
/// Asked for at the size drawn, so the decode is bounded the way
/// `ImagePipeline`'s is, and held in a small cache so scrolling the list
/// does not ask twice.
@MainActor
enum RecentThumbnails {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    static func image(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let key = url as NSURL
        if let hit = cache.object(forKey: key), hit.size.width >= size.width { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: scale, representationTypes: .thumbnail
        )
        // The completion form, taking only the CGImage across: the
        // representation object itself is not Sendable.
        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: thumbnail?.cgImage)
            }
        }
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The row's leading image, and on hover a larger one — Finder's Quick Look,
/// in miniature.
struct RecentThumbnailView: View {
    let url: URL
    let fallbackIcon: String
    let isMissing: Bool
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?
    @State private var showsPreview = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
            } else {
                Image(systemName: fallbackIcon)
                    .font(Theme.Glyph.md(.medium))
                    .foregroundStyle(Theme.Palette.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Theme.Palette.accent.opacity(isMissing ? 0.35 : 1),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
        }
        .task(id: url) { image = await RecentThumbnails.image(for: url, size: CGSize(width: 320, height: 180), scale: scale) }
        .onHover { inside in
            hoverTask?.cancel()
            guard image != nil else { return }
            if inside {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled { showsPreview = true }
                }
            } else {
                showsPreview = false
            }
        }
        .popover(isPresented: $showsPreview, arrowEdge: .trailing) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(Theme.Space.sm)
            }
        }
    }
}
