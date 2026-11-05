import SwiftUI
import LumiereKit

/// A collection's own titles, each showing the picture of the kind being
/// chosen, in a strip above the providers' offers: a adult franchise has no
/// artwork of its own anywhere, but its series do. Choosing one copies it to
/// the collection on the server.
struct TitleArtworkStrip: View {
    struct Source {
        let titles: [LibraryEntry]
        let serverURL: URL
        let pipeline: ImagePipeline
    }

    let source: Source
    let kind: JellyfinImageURL.ImageKind
    let disabled: Bool
    let onChoose: (LibraryEntry) -> Void
    @Environment(\.displayScale) private var scale

    private var offered: [(LibraryEntry, String)] {
        source.titles.compactMap { title in
            let tag = kind == .backdrop ? title.item.backdropTag : (kind == .thumb ? title.item.thumbTag : title.item.primaryTag)
            return tag.map { (title, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("From its titles")
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            if offered.isEmpty {
                Text("None of its titles has one of these.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(offered, id: \.0.id) { title, tag in
                            Button { onChoose(title) } label: { cell(title, tag: tag) }
                                .buttonStyle(.plain)
                                .disabled(disabled)
                                .labelledHelp("Use \(title.item.name)'s")
                        }
                    }
                }
            }
        }
    }

    private func cell(_ title: LibraryEntry, tag: String) -> some View {
        let wide = kind != .primary
        let width: CGFloat = wide ? 160 : 80
        let aspect = wide ? Theme.Art.backdropAspect : Theme.Art.posterAspect
        return VStack(alignment: .leading, spacing: 2) {
            RemoteImage(request: ImageRequest(serverURL: source.serverURL, itemId: title.id, kind: kind, tag: tag,
                                              displayWidth: width, aspectRatio: aspect, screenScale: scale),
                        pipeline: source.pipeline)
                .frame(width: width, height: width / aspect)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
            Text(title.item.name)
                .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1).frame(width: width, alignment: .leading)
        }
    }
}
