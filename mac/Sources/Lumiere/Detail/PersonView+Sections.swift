import SwiftUI
import LumiereKit

/// The person page's blocks: the headshot, the wall of titles, and a strip of
/// episodes per show. Split from `PersonView.swift` for the project's 300-line
/// rule; these have no state of their own, just `PersonView`'s properties.
extension PersonView {

    // MARK: - Header

    /// Face on the left, name and counts beside it.
    ///
    /// Not a backdrop hero, deliberately: a person has no artwork the server can
    /// fill a 16:9 band with, and stretching a 2:3 headshot into one is how those
    /// pages end up looking like a broken detail page. The circle is the same
    /// shape the cast row uses, at a size that makes it the subject rather than a
    /// cell — arriving here should read as having followed the portrait you
    /// clicked, which is the same reason a genre page opens with a `ShelfTitleCard`.
    @ViewBuilder
    func header(_ model: PersonModel?) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.xl) {
            portrait
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(route.name)
                    .font(Theme.Font.hero)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                // The counts, once they are known. The line is not reserved while
                // they load: this block sits above everything, so a placeholder
                // here would shift the whole page down when it filled in.
                if let summary = model?.summary {
                    Text(summary)
                        .font(Theme.Font.detailMeta)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    private var portrait: some View {
        Group {
            if let tag = route.imageTag {
                RemoteImage(
                    request: ImageRequest(
                        serverURL: serverURL, itemId: route.id, kind: .primary, tag: tag,
                        displayWidth: DetailMetrics.personPortrait,
                        aspectRatio: 1, screenScale: scale
                    ),
                    pipeline: pipeline
                )
            } else {
                Circle()
                    .fill(Theme.Palette.surfaceRaised)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(Theme.Font.hero)
                            .foregroundStyle(Theme.Palette.textDisabled)
                    }
            }
        }
        .frame(width: DetailMetrics.personPortrait, height: DetailMetrics.personPortrait)
        .clipShape(Circle())
    }

    // MARK: - Titles

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: Theme.Art.shelfPosterWidth),
            spacing: Theme.Space.tileGap,
            alignment: .top
        )]
    }

    /// Films and series as one wall rather than two.
    ///
    /// Splitting them was tried first and reads worse: for most people the two
    /// sections are four posters and one, and a heading over a single card is a
    /// heading that costs more vertical space than the thing it names. The card
    /// already says which it is — a series shows its episode badge — and the sort
    /// is by release, which is the order a career actually happened in.
    @ViewBuilder
    func titlesSection(_ model: PersonModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ShelfTitleCard(
                title: "Films & Series",
                subtitle: model.titleTotal > 0 ? countText(model.titleTotal, "title") : nil
            )
            LazyVGrid(columns: columns, spacing: Theme.Space.xl) {
                ForEach(model.titles) { entry in
                    NavigationLink(value: DetailRoute.forEntry(entry)) {
                        PosterCard(
                            entry: entry,
                            serverURL: serverURL,
                            pipeline: pipeline,
                            width: Theme.Art.shelfPosterWidth,
                            metadata: entryActions.actions(
                                for: entry, in: actionContext(model)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    // Paged on appearance rather than on a scroll offset, so the
                    // loaded window stays bounded however prolific the person is.
                    .task { await loadMoreTitles(model, near: entry) }
                }
            }
            .padding(.horizontal, Theme.Space.shelfInset)
        }
    }

    private func loadMoreTitles(_ model: PersonModel, near entry: LibraryEntry) async {
        guard model.hasMoreTitles,
              let index = model.titles.firstIndex(where: { $0.id == entry.id }),
              index >= model.titles.count - 12 else { return }
        await model.loadMoreTitles()
    }

    // MARK: - Episodes

    /// One horizontal strip per show, headed by the show's name.
    ///
    /// Grouped rather than listed flat because a flat list of episode stills is
    /// unreadable the moment a guest run is more than a handful: eleven cards
    /// titled "Episode 4" with nothing saying which programme they belong to. The
    /// heading carries the show; the cards carry the episode. Wide cards at the
    /// episode strip's width, so this row is the same row a series page shows.
    ///
    /// Known cosmetic: `WideCard` leads an episode with its series name, so under
    /// this heading each card repeats the show. That is the card doing the right
    /// thing everywhere else it is used — Continue Watching has no heading to lean
    /// on — and fixing it here would mean either a second episode card in this
    /// folder or a change to a shared component for one caller's benefit. The
    /// grouping is worth the repeated line; a flat strip of 200 stills is not.
    func episodeShelf(_ model: PersonModel, _ group: PersonEpisodeGroup) -> some View {
        DetailShelf(title: group.title) {
            ForEach(group.entries) { entry in
                // `forEntry` sends an episode to its *series* page with the episode
                // named, which is the page someone clicking one actually wants —
                // the same behaviour Next Up and Continue Watching have.
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    WideCard(
                        entry: entry, serverURL: serverURL,
                        pipeline: pipeline, width: DetailMetrics.episodeWidth,
                        metadata: entryActions.actions(for: entry, in: actionContext(model))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Episodes page on a button rather than on scroll position.
    ///
    /// The grid above can page on appearance because its cells are in one flat
    /// list. These are not: a window of episodes can extend the last strip, start
    /// a new one, or both, so "the twelfth cell from the end" is not a thing that
    /// exists here. A button is also the more honest control for a run that can be
    /// hundreds long — it says there is more, and how much.
    @ViewBuilder
    func moreEpisodes(_ model: PersonModel) -> some View {
        HStack {
            if model.isLoadingMoreEpisodes {
                ProgressView()
            } else {
                Button {
                    Task { await model.loadMoreEpisodes() }
                } label: {
                    Text("Show More Episodes (\(model.episodeTotal - model.loadedEpisodeCount) left)")
                        .font(Theme.Font.body)
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    // MARK: - Empty

    /// Two different nothings, said differently. A query that failed and a person
    /// the library genuinely has nothing else by look identical on screen, and the
    /// first is worth retrying while the second is not.
    @ViewBuilder
    func empty(_ model: PersonModel) -> some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: model.loadError == nil ? "person.crop.circle" : "exclamationmark.triangle")
                .font(Theme.Font.hero)
                .foregroundStyle(Theme.Palette.textDisabled)
            Text(model.loadError ?? "Nothing else by \(route.name) in your library")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxxl)
    }

    private func countText(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
