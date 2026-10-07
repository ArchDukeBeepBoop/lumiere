import SwiftUI
import LumiereKit

/// The signature Infuse move: a full-bleed backdrop with the title, the technical
/// badges, and a play button.
///
/// One item. Which item — and the chevrons that change it — belong to
/// `HeroSpotlight`, which wraps this. Keeping the two apart is what lets the
/// rotation hold exactly one of these at a time.
///
/// The resume track below still draws when the entry has progress, which is now
/// the uncommon case: the spotlight is unwatched titles. It stays because both
/// layouts fall back to `recentlyAdded` on a library too thin to spotlight, and
/// because an entry with progress should always say so.
///
/// The one place the app deliberately spends memory — a single 16:9 backdrop at
/// window width. It gets its own small cache so that scrolling a poster grid
/// never evicts it and forces a re-decode on the way back up.
struct HeroBackdrop: View {
    let entry: LibraryEntry
    let pipeline: ImagePipeline
    let serverURL: URL
    let capabilities: SystemCapabilities
    /// Hands an item id to the shell, which is how everything else in the app
    /// starts playback.
    var onPlay: (String) -> Void = { _ in }
    /// Why this title is the one on screen. Nil where there is nothing honest to
    /// say, which is the case a rotating spotlight is always in.
    var reason: String?

    @Environment(\.displayScale) private var scale
    @Environment(\.folderLibraryIds) private var folderLibraryIds
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle
    @State private var isHoveringResume = false

    /// The backdrop at its own 16:9, within reason: floored so a narrow window
    /// still has room for the title block, capped so the shelves under it are not
    /// pushed off a large display.
    ///
    /// Sized from the width it is actually given, not from the screen's.
    ///
    /// It used to set its outer height from `NSScreen.main`, while the image inside
    /// was sized from the layout width the `GeometryReader` reported. Those are the
    /// same number only in a full-width window: with a sidebar open, or any window
    /// short of full screen, the container was built for a wider picture than the
    /// one drawn in it — which is the other half of "the home backdrop is smaller
    /// than the series backdrop". The detail page has always derived its height
    /// from its own width, and this now does the same, so the two agree.
    var body: some View {
        Color.clear
            .aspectRatio(Theme.Art.backdropAspect, contentMode: .fit)
            .frame(
                minHeight: Theme.Art.heroHeight, maxHeight: Theme.Art.heroHeightMax
            )
            // The aspect box sets the *height* and nothing else. Once the window is
            // wider than 16:9 of the height cap — which is exactly what hiding the
            // sidebar does — a fitted box is narrower than the window, and the hero
            // was being drawn inside it: a band of artwork with bare page beside it.
            // Taking the full width back here, before the overlay, keeps the picture
            // full-bleed at any window size while the height still follows the
            // artwork's own shape.
            .frame(maxWidth: .infinity)
            .overlay { content }
    }

    private var content: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // No mask, and only the text band shaded.
                //
                // This had two full-strength layers — a gradient mask dissolving the
                // picture's bottom edge into the page, and a wash of the canvas
                // colour over the lower half. Both are gone; the picture now runs to
                // the bottom at full strength and `BackdropTextWash` shades only the
                // strip the title actually sits on. Removing the mask is what made
                // the wash necessary again: with the artwork no longer faded away
                // under the title, the text has a photograph behind it rather than
                // the page's own colour.
                RemoteImage(
                    request: .backdrop(
                        for: entry,
                        serverURL: serverURL,
                        width: geometry.size.width,
                        scale: scale,
                        // The show's own backdrop, not this episode's still.
                        //
                        // Without this the hero took the episode's Primary image —
                        // often the frame Lumiere generated itself — so the top of
                        // the home screen was a grab from the middle of an episode
                        // rather than the artwork for the series. A hero is about
                        // the show; the episode is named in the line beneath it.
                        preferSeriesThumb: true
                    ),
                    pipeline: pipeline,
                    // Text is drawn on this. See `Theme.Palette.artworkPlaceholder`.
                    carriesText: true
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                // Over the picture and under `details`, which is the only order that
                // works: the title block has to be read against it, not through it.
                .overlay { BackdropTextWash() }

                details
            }
        }
    }

    /// Opaque through the middle, transparent at the edges the picture meets the
    /// page on.
    ///
    /// Weighted heavily to the bottom, which is the edge that matters: the shelves
    /// start immediately under it, so that is the join a reader's eye follows. The
    /// sides and top get a much shorter fade — enough to soften the cut against the
    /// window, not enough to eat into the composition.
    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            title
            metadataLine

            if !badges.isEmpty {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(badges, id: \.0) { text, role in
                        Badge(text: text, role: role)
                    }
                }
            }

            // Above the synopsis, and set apart from it. The synopsis says what
            // the thing is; this says why you are being shown it, and they are
            // different kinds of sentence — running them together as one grey
            // paragraph is how the reason stops being read.
            if let reason {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(reason)
                        .font(Theme.Font.cardTitleLarge)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.Palette.onArtworkText)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                .padding(.bottom, 2)
            }

            if let overview = entry.item.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Font.body)
                    // On-artwork colours, not the page's. These sit on a photograph
                    // now — the mask that used to dissolve the picture away under
                    // this block is gone — and `textSecondary` is a mid grey chosen
                    // to sit on the canvas, which over a bright frame is barely
                    // there. White at 78% with a shadow reads on any still.
                    .foregroundStyle(Theme.Palette.onArtworkTextMuted)
                    .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                    .lineLimit(3)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            resumeTrack
            actions
        }
        // The shelves' inset horizontally, so the hero's title starts on the same
        // line as the first poster of every row under it. Vertically it keeps the
        // old value: that gap is about the backdrop the block sits on rather than
        // about the page's left edge.
        .padding(.horizontal, Theme.Space.shelfInset)
        .padding(.vertical, Theme.Space.xxl)
    }

    @ViewBuilder
    private var title: some View {
        // A logo, when the server has one, is what makes this look like a film
        // rather than a database row.
        if let logo = ImageRequest.logo(
            for: entry, serverURL: serverURL,
            width: Theme.Art.heroLogoWidth, scale: scale
        ) {
            RemoteImage(request: logo, pipeline: pipeline, contentMode: .fit)
                .frame(
                    maxWidth: Theme.Art.heroLogoWidth,
                    maxHeight: Theme.Art.heroLogoHeight,
                    alignment: .leading
                )
        } else {
            // The series for an episode, the filename for a loose file in a folder
            // library, the metadata name otherwise. See `FolderTitle`.
            Text(entry.item.seriesName
                 ?? FolderTitle.title(
                     for: entry, style: titleStyle, folderLibraryIds: folderLibraryIds
                 ))
                .font(Theme.Font.hero)
                .foregroundStyle(Theme.Palette.onArtworkText)
                // A heavier shadow than the lines below it: the title is set large
                // enough to cross several parts of a frame at once, so it meets
                // more variety of brightness than anything else here.
                .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
                .lineLimit(2)
        }
    }

    /// How far in you are, when you are part-way in. The bar carries the position
    /// so the Play button can stay a single short word rather than a timecode.
    @ViewBuilder
    private var resumeTrack: some View {
        if let progress = entry.progress {
            HStack(spacing: Theme.Space.sm) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.border)
                    Capsule()
                        .fill(Theme.Palette.accentOnArtwork)
                        .frame(width: Theme.Art.heroProgressWidth * progress)
                }
                .frame(width: Theme.Art.heroProgressWidth, height: 3)

                if let remaining = entry.remainingText {
                    Text(remaining)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
        }
    }

    private var metadataLine: some View {
        Text(metadataParts.joined(separator: " · "))
            .font(Theme.Font.body)
            // See the synopsis above: page colours on a photograph.
            .foregroundStyle(Theme.Palette.onArtworkTextMuted)
            .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
            // One line, always. An episode with a long name and three genres wraps
            // to two here and pushes the buttons into the shelf below it.
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// One loud action and one quiet one.
    ///
    /// The primary is untinted rather than gold — `playButton` exists for exactly
    /// this, and using it here is what makes the hero's Play and the detail
    /// screen's Play the same button rather than two designs.
    ///
    /// When the hero is a *series* — which it is whenever nothing is in progress
    /// and the newest thing added leads — there is no single file to send to the
    /// player, so the primary opens the show instead of pretending to play it.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Theme.Space.md) {
            if isPlayable {
                Button { onPlay(entry.item.id) } label: {
                    primaryLabel(icon: "play.fill", text: resumeLabel)
                }
                .buttonStyle(.plain)
                .scaleEffect(isHoveringResume ? Theme.Elevation.hoverScale : 1)
                .animation(Theme.Motion.hover, value: isHoveringResume)
                .onHover { isHoveringResume = $0 }

                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    secondaryLabel("More Info")
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    primaryLabel(icon: "info.circle.fill", text: "More Info")
                }
                .buttonStyle(.plain)
                .scaleEffect(isHoveringResume ? Theme.Elevation.hoverScale : 1)
                .animation(Theme.Motion.hover, value: isHoveringResume)
                .onHover { isHoveringResume = $0 }
            }
        }
        .padding(.top, Theme.Space.xs)
    }

}
