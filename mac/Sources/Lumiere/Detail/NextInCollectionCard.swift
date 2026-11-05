import SwiftUI
import LumiereKit

/// "Next in Monogatari": the title that follows this one in its franchise or
/// film series, as a card under the header — the question a franchise page
/// answers, asked before scrolling to the list that holds the whole order.
///
/// The server decides what "next" is: an anime franchise's own order (as it
/// came out, kept by the AniList pass), or release date in a film series.
struct NextInCollectionCard: View {
    let next: LibraryEntry
    let collection: String
    let pipeline: ImagePipeline
    let serverURL: URL
    @Environment(\.displayScale) private var scale
    @State private var isHovering = false

    private let posterWidth: CGFloat = 54

    var body: some View {
        NavigationLink(value: DetailRoute.forEntry(next)) {
            HStack(spacing: Theme.Space.md) {
                RemoteImage(
                    request: .poster(for: next, serverURL: serverURL, width: posterWidth, scale: scale),
                    pipeline: pipeline
                )
                .frame(width: posterWidth, height: posterWidth / Theme.Art.posterAspect)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Next in \(collection)")
                        .font(Theme.Font.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                        .lineLimit(1)
                    Text(next.item.name)
                        .font(Theme.Font.cardTitleLarge)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Space.sm)
                Image(systemName: "chevron.right")
                    .font(Theme.Glyph.sm())
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(Theme.Space.sm)
            .padding(.trailing, Theme.Space.xs)
            .frame(maxWidth: 420, alignment: .leading)
            .background(isHovering ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .accessibilityLabel("Next in \(collection): \(next.item.name), \(detail)")
    }

    /// Year, kind, and whether it has been seen.
    private var detail: String {
        var parts: [String] = []
        if let year = next.item.productionYear { parts.append(String(year)) }
        parts.append(next.item.itemType == .series ? "Show" : "Film")
        parts.append(next.isPlayed ? "Watched" : (next.progress != nil ? "In progress" : "Not watched"))
        return parts.joined(separator: " · ")
    }
}
