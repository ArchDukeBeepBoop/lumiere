import SwiftUI
import LumiereKit

/// The episode strip and the two chevrons that page it.
///
/// Split from SeasonEpisodeList.swift for the project's 300-line rule.
///
/// The strip was a single continuous run of stills with no indication that it ran
/// off the side of the window at all: a season of twenty-four episodes showed
/// three, and finding episode nineteen meant discovering that this particular row
/// happened to scroll. The chevrons say that it does, and move it a screenful at a
/// time — a stride, not a nudge, because the point of pressing an arrow rather
/// than flicking a trackpad is that it lands somewhere predictable.
///
/// Scrolling by hand still works exactly as before; the chevrons are an addition
/// to it, not a replacement for it.
extension SeasonEpisodeList {

    /// Names the coordinate space the offset is measured in. A string constant
    /// rather than a literal at both ends, since the two have to agree and a typo
    /// between them fails silently — the offset simply never changes.
    private static var stripSpace: String { "episodeStrip" }

    var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // An eager HStack, deliberately.
                //
                // This was made lazy to avoid building every cell of a long strip,
                // and it left blank space at the end of shelves: a LazyHStack
                // estimates its width from the cells it has realised, and these
                // shelves hand it an opaque @ViewBuilder rather than a ForEach it
                // can count, so the estimate is wrong and the scroll view extends
                // past the last tile into nothing. One season is the bound here,
                // which for a merged anime series is a few hundred cells — hence
                // the care taken in EpisodeThumbnail to leave no shadow installed
                // at rest.
                HStack(alignment: .top, spacing: Theme.Space.tileGap) {
                    ForEach(model.episodes) { episode in
                        // Explicit, because `proxy.scrollTo` is aiming at it. A
                        // `ForEach` over `Identifiable` supplies an implicit id, and
                        // every other scrolled list in this app still states it —
                        // the folder grid and the music list both do. This strip was
                        // the one that did not, and it is the one whose chevrons
                        // were reported as doing nothing.
                        cell(episode).id(episode.id)
                    }
                    nextSeasonTile
                }
                .detailMargin()
                // Room for the hover lift and its shadow, as every other shelf has.
                .padding(.vertical, Theme.Space.md)
                .background { contentReader }
            }
            .coordinateSpace(name: Self.stripSpace)
            .background { viewportReader }
            .overlay(alignment: .leading) { pageButton(forward: false, proxy: proxy) }
            .overlay(alignment: .trailing) { pageButton(forward: true, proxy: proxy) }
            .onAppear {
                if let heroId = model.heroEntry?.id {
                    proxy.scrollTo(heroId, anchor: .leading)
                }
            }
        }
    }

    // MARK: - Cells

    private func cell(_ episode: LibraryEntry) -> some View {
        EpisodeThumbnail(
            entry: episode,
            isSelected: episode.id == model.heroEntry?.id,
            pipeline: pipeline,
            serverURL: serverURL,
            scale: scale,
            onSelect: { model.selectEpisode(episode.id) },
            onPlay: onPlayEpisode.map { play in { play(episode.id) } }
        )
        .contextMenu {
            if let onToggleEpisodeWatched {
                Button(
                    episode.isPlayed
                        ? "Mark as Unwatched" : "Mark as Watched"
                ) {
                    onToggleEpisodeWatched(
                        episode.id, !episode.isPlayed
                    )
                }
                Divider()
            }
            if let onEditEpisode {
                Button("Edit Metadata…") { onEditEpisode(episode.id) }
            }
            if let onGenerateThumbnail {
                // The warning is in the label, not a tooltip. macOS shows no
                // tooltip on a context-menu item, so the one place in the app
                // that said freezing a thumbnail also stops the synopsis
                // updating was unreachable — a `.help` on a menu row renders
                // nothing at all.
                Button("Freeze Thumbnail from File…") {
                    onGenerateThumbnail(episode.id)
                }
            }
            if let onEpisodeArtwork {
                Button("Choose or Remove Artwork…") {
                    onEpisodeArtwork(episode.id)
                }
            }
            if onRemoveEpisode != nil || onDeleteEpisode != nil {
                Divider()
            }
            if let onRemoveEpisode {
                Button("Remove from Library…") { onRemoveEpisode(episode) }
            }
            if let onDeleteEpisode {
                Button("Delete File…", role: .destructive) { onDeleteEpisode(episode) }
            }
        }
        .id(episode.id)
    }

    // MARK: - Measurement

    /// Reports where the content sits inside the scroll view, and how wide it is.
    ///
    /// `onChange` on a value read from a `GeometryReader`, rather than a preference
    /// key: a preference action is `@Sendable` and cannot touch this view's state
    /// under Swift 6 without a hop through the main actor, where this closure is
    /// already on it. Cheap either way — the reader draws `Color.clear` and takes
    /// its size from the stack it backs.
    private var contentReader: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named(Self.stripSpace))
            Color.clear
                .onChange(of: frame.minX, initial: true) { _, minX in
                    scrollOffset = -minX
                }
                .onChange(of: frame.width, initial: true) { _, width in
                    contentWidth = width
                }
        }
    }

    private var viewportReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onChange(of: geometry.size.width, initial: true) { _, width in
                    viewportWidth = width
                }
        }
    }

    // MARK: - Paging

    /// A point of slack. Sub-pixel rounding leaves the offset a hair short of its
    /// limit at the end of a strip, and without this the forward chevron never
    /// quite goes away.
    private var slack: CGFloat { 1 }

    /// Whether the strip has been measured at all.
    ///
    /// Both readers start at zero, and every test below is a comparison against
    /// zero — so before the first geometry callback lands, "can I page forward"
    /// answers no, and the chevron is drawn at `opacity(0)` with hit testing off. A
    /// control that is invisible *and* dead because the layout has not reported yet
    /// is indistinguishable from one that is broken, and on a page whose episodes
    /// arrive asynchronously that window is not always brief.
    private var isMeasured: Bool { contentWidth > 0 && viewportWidth > 0 }

    private var canPageBack: Bool { isMeasured && scrollOffset > slack }

    /// Forward is available when there is more strip than viewport — or when the
    /// strip has more episodes than obviously fit and nothing has been measured yet,
    /// so the first press is never swallowed.
    private var canPageForward: Bool {
        guard isMeasured else { return model.episodes.count > 1 }
        return contentWidth - viewportWidth - scrollOffset > slack
    }

    /// The distance between one still's leading edge and the next.
    private var pitch: CGFloat { DetailMetrics.episodeWidth + Theme.Space.tileGap }

    /// How many whole stills fit on screen — the distance one press covers.
    ///
    /// Floored, and never less than one: a window narrow enough to show a single
    /// still must still advance by that one rather than by nothing at all. Named
    /// around Swift's own `stride`, which is a global function this would shadow.
    private var pageStride: Int { max(1, Int(viewportWidth / pitch)) }

    /// Which episode is currently at the leading edge.
    ///
    /// Derived from the offset rather than remembered, so a strip that was
    /// scrolled by hand pages on from where it actually is. The tiles are all one
    /// width, so this is arithmetic rather than a search: the content begins at the
    /// page margin, and every still after that is one `pitch` further along.
    private var leadingIndex: Int {
        guard pitch > 0 else { return 0 }
        let index = ((scrollOffset - Theme.Space.shelfInset) / pitch).rounded()
        return min(max(Int(index), 0), max(model.episodes.count - 1, 0))
    }

    /// Faded out rather than removed when there is nothing that way.
    ///
    /// A conditional branch would take the button out of the view tree, and a view
    /// that does not exist cannot animate its own departure — the chevrons popped.
    /// Kept in place at zero opacity and out of the hit-testing, they cross-fade,
    /// and the geometry that drives them updates continuously as the strip is
    /// dragged.
    private func pageButton(forward: Bool, proxy: ScrollViewProxy) -> some View {
        let isAvailable = forward ? canPageForward : canPageBack
        return Button {
            page(forward: forward, proxy: proxy)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(
                    width: DetailMetrics.stripChevron,
                    height: DetailMetrics.stripChevron
                )
                // Material rather than a palette fill: the disc sits on a still,
                // so what is behind it changes with every show, and a flat surface
                // colour reads as a hole punched in the artwork.
                .liquidGlass(Circle(), .regularMaterial)
                .overlay {
                    Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .labelledHelp(forward ? "Later episodes" : "Earlier episodes")
        .padding(.horizontal, Theme.Space.md)
        // Centred on the still rather than on the cell. An overlay centres itself
        // in the scroll view, which is as tall as the stills *plus* the two lines
        // of type under them, so without this the chevrons sit visibly low — level
        // with the runtimes rather than with the artwork.
        .padding(.bottom, Theme.Space.sm + DetailMetrics.episodeLabelHeight)
        .opacity(isAvailable ? 1 : 0)
        .allowsHitTesting(isAvailable)
        .animation(Theme.Motion.hover, value: isAvailable)
    }

    private func page(forward: Bool, proxy: ScrollViewProxy) {
        // One tile when the viewport is unknown, rather than `max(1, 0/pitch)` worth
        // of guesswork. Pressing a chevron always moves the strip.
        let stride = isMeasured ? pageStride : 1
        let target = forward ? leadingIndex + stride : leadingIndex - stride
        let clamped = min(max(target, 0), max(model.episodes.count - 1, 0))
        guard model.episodes.indices.contains(clamped) else { return }
        withAnimation(Theme.Motion.transition) {
            proxy.scrollTo(model.episodes[clamped].id, anchor: .leading)
        }
    }

    /// Where a season ends, the next one — "what now?" answered in the place
    /// the question comes up, not in a picker at the top of the list.
    @ViewBuilder
    var nextSeasonTile: some View {
        if !model.episodes.isEmpty,
           let current = model.seasons.firstIndex(where: { $0.id == model.selectedSeasonId }),
           current + 1 < model.seasons.count {
            let next = model.seasons[current + 1]
            Button { Task { await model.selectSeason(next.id) } } label: {
                VStack(spacing: Theme.Space.xs) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .semibold))
                    Text(next.item.name)
                        .font(Theme.Font.cardTitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Theme.Art.episodeThumbWidth * 0.6,
                       height: Theme.Art.episodeThumbWidth * 9 / 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Go on to \(next.item.name)")
        }
    }
}
