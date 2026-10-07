import SwiftUI
import LumiereKit

struct WideCard: View {
    let entry: LibraryEntry
    let serverURL: URL
    let pipeline: ImagePipeline
    var width: CGFloat = Theme.Art.episodeThumbWidth
    /// Continue Watching uses the series thumb so a row of cards is visually
    /// consistent instead of a set of unrelated episode stills.
    var preferSeriesThumb: Bool = false
    /// Replaces the drawn title where the item's own name does not identify it.
    ///
    /// An override rather than a `TitleStyle` because the choice belongs to the
    /// surface and not to the user: their title setting stays whatever they chose,
    /// and only the one view that knows its names are useless overrides it. See
    /// `FolderBrowserView.fileTitle`.
    var titleOverride: String?
    var metadata: MetadataActions?

    @State private var isHovering = false
    /// Starts playback rather than opening the page.
    ///
    /// The disc was drawn and nothing was behind it: hovering a Continue Watching
    /// card put a play button on the still, and clicking it fell through to the
    /// enclosing `NavigationLink` and opened the detail page. A button that does the
    /// same thing as the card it is drawn on is not a button, it is a picture of
    /// one. Nil where a surface has no way to start playback, and then the disc is
    /// absent too rather than decorative.
    var onPlay: (() -> Void)?
    /// An episode that arrived after the show was last watched. One word in
    /// the accent, ahead of the caption — the unwatched count says how many,
    /// this says which is news.
    var isNew = false

    @Environment(\.displayScale) private var scale
    /// Off by default. See `ImageRequest.backdrop`.
    @AppStorage("unifiedEpisodeArt") private var unifiedEpisodeArt = false
    /// See `FolderLibraries`. Empty outside the app's own view tree, which makes
    /// this a no-op in previews rather than a crash.
    @Environment(\.folderLibraryIds) private var folderLibraryIds
    @Environment(\.discreetArtLibraryIds) private var discreetArtLibraryIds
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle

    /// Same rule as `PosterCard`: the treatment follows the size. A wide card is
    /// "large" once it is past the old episode-thumb width, which is every card on
    /// the home screen and none in an episode list.
    private var isLarge: Bool { width > Theme.Art.episodeThumbWidth }
    private var corner: CGFloat {
        isLarge ? Theme.Radius.posterLarge : Theme.Radius.poster
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            artwork
            .frame(width: width, height: width / Theme.Art.thumbAspect)
            .coverHeldBack(libraryId: entry.item.libraryId, isHovering: isHovering)
            .keyboardCard(id: entry.id, cornerRadius: corner)
            .overlay(alignment: .center) { playAffordance }
            .overlay(alignment: .bottom) { progressBar }
            // Clipped last, so the corner marker and the progress bar follow the
            // rounded edge instead of squaring it off.
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .tvLift(corner: corner, size: CGSize(width: width, height: width / Theme.Art.thumbAspect))
            // The same lift a poster gets, at the same amount: a shelf of wide
            // cards and a shelf of posters have to feel like one surface.
            .shadow(
                color: isHovering ? Theme.Palette.cardShadow : .clear,
                radius: isHovering ? Theme.Elevation.hoverShadow : 0,
                y: isHovering ? Theme.Elevation.hoverShadowY : 0
            )
            .scaleEffect(isHovering ? Theme.Elevation.hoverScale : 1)
            .animation(Theme.Motion.hover, value: isHovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(isLarge ? Theme.Font.cardTitleLarge : Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    // Two lines for a filename, and cut from the middle. A release
                    // name carries what it is at the front and how it was encoded
                    // at the back; truncating the tail keeps the least useful half.
                    // See `PosterCard`: an overridden title is a filename, and
                    // these differ in the middle as often as at the front, so
                    // middle-truncating one is how you get two tiles reading the
                    // same. Wrapped in full instead.
                    // Two lines for a filename, always exactly two, cut from the
                    // middle. It used to wrap in full, which is fine in a row and
                    // wrong in a grid: a `LazyVGrid` row is as tall as its tallest
                    // cell, so one four-line filename pushed the whole next row
                    // down while a row of short names stayed tight — the uneven
                    // spacing on the folder walls. `reservesSpace` is the half that
                    // makes it uniform, since a one-line name would otherwise still
                    // yield a shorter cell. Middle, because release names differ
                    // from each other at the back as often as the front.
                    .lineLimit(titleOverride == nil ? 1 : 2,
                               reservesSpace: titleOverride != nil)
                    .truncationMode(titleOverride == nil ? .tail : .middle)
                (isNew
                    ? Text("New · ").foregroundStyle(Theme.Palette.accent) + Text(detailText)
                    : Text(detailText))
                    .font(isLarge ? Theme.Font.captionLarge : Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .modifier(MetadataContextMenu(actions: metadata))
        .contentShape(Rectangle())
        .onHover { isHovering = $0; HomeAmbient.shared.hover(entry, $0) }
    }

    /// A drawn card when the server has no wide artwork for this item, rather than a
    /// stretched poster or an empty grey rectangle.
    @ViewBuilder
    private var artwork: some View {
        if let request = ImageRequest.backdrop(
            for: entry, serverURL: serverURL, width: width, scale: scale,
            preferSeriesThumb: preferSeriesThumb,
            unifiesEpisodeArt: unifiedEpisodeArt,
            primaryIsWide: entry.item.libraryId.map(folderLibraryIds.contains) ?? false,
            showArtOnly: entry.item.libraryId.map(discreetArtLibraryIds.contains) ?? false
        ) {
            RemoteImage(request: request, pipeline: pipeline)
        } else {
            GeneratedThumb(title: titleText, subtitle: detailText)
        }
    }

    @ViewBuilder
    private var playAffordance: some View {
        if isHovering, let onPlay {
            Button(action: onPlay) { playDisc }
                .buttonStyle(.plain)
                // Only the disc takes the click. Without this the button's frame
                // covers the whole still and the card stops opening its page.
                .contentShape(Circle())
        }
    }

    private var playDisc: some View {
        Group {
            // Grown with the card for the same reason as the unwatched corner: a
            // 40pt disc centred on a 384pt still reads as a dot, not a button.
            Circle()
                .fill(Theme.Palette.onArtworkStrong)
                .frame(width: isLarge ? 54 : 40, height: isLarge ? 54 : 40)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: isLarge ? 20 : 15))
                        .foregroundStyle(Theme.Palette.onPlayerChrome)
                }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress = entry.progress {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Palette.onArtwork)
                    Rectangle()
                        .fill(Theme.Palette.accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)
        }
    }

    /// Episodes lead with the series name — a row of episode titles with no
    /// context is unreadable.
    private var titleText: String {
        if let titleOverride { return titleOverride }
        if entry.item.itemType == .episode, let series = entry.item.seriesName {
            return series
        }
        // A loose file in a folder library is its filename. See `libraryTitle`.
        return FolderTitle.title(
            for: entry, style: titleStyle, folderLibraryIds: folderLibraryIds
        )
    }

    private var detailText: String {
        var parts: [String] = []
        if entry.item.itemType == .episode, let code = entry.item.episodeCode() {
            parts.append(code)
        }
        if let remaining = entry.remainingText {
            parts.append(remaining)
        } else if let ticks = entry.item.runTimeTicks, ticks > 0 {
            // Not started: how long it is, which is the deciding fact at night —
            // and for a film, when it would end if it started now.
            let seconds = Double(ticks) / 10_000_000
            parts.append(Self.length(seconds))
            if entry.item.itemType == .movie {
                parts.append("ends " + Date().addingTimeInterval(seconds)
                    .formatted(date: .omitted, time: .shortened))
            }
        } else if let year = entry.item.productionYear {
            parts.append(String(year))
        }
        return parts.joined(separator: " · ")
    }

    /// "23 min", "1 h 52 min".
    static func length(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
