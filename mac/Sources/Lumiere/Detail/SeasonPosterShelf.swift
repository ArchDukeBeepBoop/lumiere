import SwiftUI
import LumiereKit

/// The seasons of a series, as posters, under the episode strip.
///
/// The season picker above the strip is a menu, and a menu hides what it holds: on
/// a show with nine seasons the only way to see that there *are* nine is to open
/// it, and the artwork someone chose for each one is never visible at all. A row of
/// posters is how every other surface in this app presents a set of things to
/// choose between, and it is what makes per-season artwork worth setting.
///
/// Selecting a poster changes the strip above rather than navigating. That is the
/// same in-place browsing the episode thumbnails do, and for the same reason: a
/// season is not a destination, it is which slice of this page you are looking at.
struct SeasonPosterShelf: View {
    let seasons: [LibraryEntry]
    let selectedId: String?
    let serverURL: URL
    let pipeline: ImagePipeline
    let onSelect: (String) -> Void
    /// Right-click actions per season. Nil in a context with no `AppModel` — the
    /// demo library, previews — so those get no menu rather than a broken one.
    var actions: ((LibraryEntry) -> MetadataActions?)?
    /// season id → episode count.
    var episodeCounts: [String: Int] = [:]

    /// Between a library tile (140) and a home shelf's poster (200).
    ///
    /// The first pass drew these at 124, which read as a strip of thumbnails rather
    /// than as artwork: an episode still on this page is 360 wide and 202 tall, so a
    /// 124 poster stood *shorter* than the row above it despite being the taller
    /// shape. At 160 it is 240 tall — clearly the largest thing in the section,
    /// which is right for the only artwork on the page anybody chooses by hand.
    ///
    /// Still short of the 200 the Related shelf uses. That row is the page's exit,
    /// and a season is somewhere you already are.
    private var posterWidth: CGFloat { 160 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Seasons")
                .font(Theme.Font.shelfTitle)
                .tracking(-0.4)
                .foregroundStyle(Theme.Palette.textPrimary)
                .detailMargin()

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Space.tileGap) {
                        ForEach(seasons) { season in
                            poster(season).id(season.id)
                        }
                    }
                    .detailMargin()
                    // Room for the hover lift and its shadow, as every shelf has.
                    .padding(.vertical, Theme.Space.md)
                }
                // The same chevrons the episode strip has. This shelf shipped
                // without them, which on a twelve-season show left the only way
                // along it a trackpad swipe — and made the row above it look like
                // the one place in the app where a horizontal list is navigable.
                .overlay(alignment: .leading) { chevron(forward: false, proxy: proxy) }
                .overlay(alignment: .trailing) { chevron(forward: true, proxy: proxy) }
                // Opens on the season being shown rather than on season one.
                .onAppear {
                    guard let selectedId else { return }
                    proxy.scrollTo(selectedId, anchor: .center)
                }
                .onChange(of: selectedId) { _, id in
                    guard let id else { return }
                    withAnimation(Theme.Motion.transition) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Nil rather than an empty string when the count is unknown, so the card falls
    /// back to its own caption instead of drawing a blank line that shifts the row.
    private func caption(for season: LibraryEntry) -> String? {
        guard let count = episodeCounts[season.id], count > 0 else { return nil }
        return "\(count) episode\(count == 1 ? "" : "s")"
    }

    /// Steps one screenful of posters, and keeps the selected season in view.
    ///
    /// Index arithmetic rather than measured geometry: every tile here is one width,
    /// so "four along" is four, and there is no scroll offset to read. Always
    /// enabled when there is somewhere to go — a chevron that hides itself because
    /// layout has not reported yet is the failure the episode strip had.
    private func chevron(forward: Bool, proxy: ScrollViewProxy) -> some View {
        let index = seasons.firstIndex { $0.id == selectedId } ?? 0
        let target = forward ? min(index + 1, seasons.count - 1) : max(index - 1, 0)
        let isAvailable = seasons.count > 1 && target != index

        return Button {
            withAnimation(Theme.Motion.transition) {
                proxy.scrollTo(seasons[target].id, anchor: .center)
            }
            onSelect(seasons[target].id)
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(
                    width: DetailMetrics.stripChevron, height: DetailMetrics.stripChevron
                )
                .liquidGlass(Circle(), .regularMaterial)
                .overlay { Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .labelledHelp(forward ? "Next season" : "Previous season")
        .padding(.horizontal, Theme.Space.md)
        // Level with the artwork rather than with the captions beneath it.
        .padding(.bottom, Theme.Space.sm + DetailMetrics.episodeLabelHeight)
        .opacity(isAvailable ? 1 : 0)
        .allowsHitTesting(isAvailable)
        .animation(Theme.Motion.hover, value: isAvailable)
    }

    private func poster(_ season: LibraryEntry) -> some View {
        Button {
            onSelect(season.id)
        } label: {
            PosterCard(
                entry: season, serverURL: serverURL, pipeline: pipeline,
                width: posterWidth,
                metadata: actions?(season),
                // How many episodes, rather than the name of the show. The computed
                // caption for a season is its series name, which is right in a
                // search result and pure noise here — every card on this page would
                // repeat the title at the top of it.
                subtitleOverride: caption(for: season)
            )
            // The current season, marked the way the picker's tick marks it.
            //
            // An overlay rather than a border on the card: `PosterCard` rounds its
            // own artwork, and a stroke applied outside that would sit square
            // around a rounded image. Drawn at the card's own radius instead, and
            // only on the art — the title below it is not part of the tile.
            .overlay(alignment: .top) {
                if season.id == selectedId {
                    RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous)
                        .strokeBorder(Theme.Palette.accent, lineWidth: 2)
                        .frame(width: posterWidth, height: posterWidth * 3 / 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(season.item.name)
        .accessibilityAddTraits(season.id == selectedId ? [.isSelected] : [])
    }
}
