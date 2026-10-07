import SwiftUI
import LumiereKit

/// Cast, chapters, extras and similar-items — the shelves below the header that
/// every detail page shares. Split out of `DetailView.swift` to stay under the
/// project's 300-line-per-file rule; these have no state of their own, just
/// `DetailView`'s existing properties.
extension DetailView {
    // MARK: - Cast

    /// "Cast & Crew" on every page now, films included — see `DetailModel.credits`
    /// for why the two page kinds stopped disagreeing about who counts as credited.
    func castShelf(_ cast: [Person], creditedTo: String? = nil) -> some View {
        DetailShelf(title: "Cast & Crew", subtitle: creditedTo) {
            // Everyone, not the first twenty. The cap was invisible in the worst
            // way: a row that simply stopped, with no indication there were more
            // people in it, on exactly the titles with the largest casts.
            ForEach(cast, id: \.id) { person in
                // A link only where the server gave the credit an id — see
                // `PersonRoute.forPerson`. A cell with no id stays a plain cell
                // rather than a control that opens an empty page, which is the
                // one thing worse than not being clickable.
                if let route = PersonRoute.forPerson(person) {
                    NavigationLink(value: route) {
                        castMember(person)
                    }
                    .buttonStyle(.plain)
                } else {
                    castMember(person)
                }
            }
        }
    }

    /// Portraits at 140pt.
    ///
    /// The cast row is the one shelf whose cells are not artwork, so its size comes
    /// from its neighbours rather than from anything intrinsic: 88 read as a
    /// footnote beside shelves carrying 200pt posters, exactly as 72 read as one
    /// beside 120pt ones, and 120 does beside 360pt stills. The rule that has held
    /// through every one of those moves is that a face should be about as wide as
    /// the name under it.
    private var castPortrait: CGFloat { DetailMetrics.castPortrait }

    /// Headshot, character, actor — the TV app's cell, in its order.
    ///
    /// The two lines used to run the other way round, with the actor's name on top
    /// and the character underneath in grey. Both orders show the same two facts,
    /// but the row is read while asking "who is that?" of a face on screen, and the
    /// answer to that question is the character; the actor is what you then want to
    /// be told. Setting the character first also gives the row a consistent first
    /// line for crew, whose job title — Director, Writer, Producer — occupies
    /// exactly the same slot as a character does.
    func castMember(_ person: Person) -> some View {
        VStack(spacing: Theme.Space.sm) {
            Group {
                if let id = person.id, let tag = person.primaryImageTag {
                    RemoteImage(
                        request: ImageRequest(
                            serverURL: serverURL, itemId: id, kind: .primary, tag: tag,
                            displayWidth: castPortrait, aspectRatio: 1, screenScale: scale
                        ),
                        pipeline: pipeline
                    )
                } else {
                    Circle()
                        .fill(Theme.Palette.surfaceRaised)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Theme.Palette.textDisabled)
                        }
                }
            }
            .frame(width: castPortrait, height: castPortrait)
            .clipShape(Circle())

            // `cardTitleLarge`/`captionLarge`, the pair every other large tile in
            // the app labels itself with. Two 11pt lines under a circle this size
            // were the same mismatch a 12pt title under a 200pt poster was.
            //
            // Both lines are drawn even when only one has anything in it, so the
            // portraits along the row stay on one baseline — the same reason the
            // episode cells reserve their runtime line.
            VStack(spacing: Theme.Space.xxs) {
                Text(billing(person) ?? person.name ?? "Unknown")
                    .font(Theme.Font.cardTitleLarge)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(billing(person) == nil ? " " : (person.name ?? " "))
                    .font(Theme.Font.captionLarge)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: DetailMetrics.castCellWidth)
    }

    /// What this person did: an actor's character, or a crew member's job. Nil
    /// where the server gave neither, in which case the name takes the first line
    /// on its own rather than being pushed under an empty label.
    private func billing(_ person: Person) -> String? {
        [person.role, person.type]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    // MARK: - Chapters

    func chapterList(_ chapters: [Chapter]) -> some View {
        DetailSection(title: "Chapters") {
            // Wider cells and `md` between them. At a 200pt minimum against a 40pt
            // page inset a wide window fitted seven columns of near-empty chips;
            // 260 gives a chapter name room to be read rather than truncated, which
            // is the only reason to list them.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: Theme.Space.md)],
                spacing: Theme.Space.md
            ) {
                ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                    HStack(spacing: Theme.Space.md) {
                        Text(timecode(chapter.startSeconds))
                            .font(Theme.Font.timecode)
                            .foregroundStyle(Theme.Palette.accent)
                        Text(chapter.name ?? "Chapter \(index + 1)")
                            .font(Theme.Font.captionLarge)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.sm)
                    .background(Theme.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
            }
        }
    }

    /// Forwards to the one implementation. See `Timecode`.
    func timecode(_ seconds: Double) -> String {
        Timecode.string(seconds)
    }

    // MARK: - Similar

    /// Trailers, featurettes, behind-the-scenes.
    ///
    /// Wide cards rather than posters: an extra has no poster of its own, so a 2:3
    /// cell would show the parent's artwork four times over. These play directly
    /// instead of navigating — there is no detail page worth opening for a
    /// two-minute featurette.
    func extrasShelf(_ entries: [LibraryEntry], model: DetailModel, title: String = "Extras") -> some View {
        DetailShelf(title: title) {
            ForEach(entries) { entry in
                Button {
                    onPlay(entry.item.id)
                } label: {
                    // The episode strip's width, not `episodeThumbWidth` (240).
                    // Extras sit two shelves below the episodes on a series page
                    // and the two rows of 16:9 cards have to be the same card.
                    WideCard(
                        entry: entry, serverURL: serverURL,
                        pipeline: pipeline, width: DetailMetrics.episodeWidth,
                        titleOverride: ExtrasGrouping.name(of: entry, showName: model.entry?.item.name ?? ""),
                        // The related shelf's menu, for the same reason it has one:
                        // an extra is an item on the server with artwork and a title
                        // that can be wrong, and a trailer with the wrong thumbnail
                        // was the one card on this page nothing could fix.
                        metadata: relatedActions(entry, model: model)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Posters at the home shelf's width.
    ///
    /// This shelf is the page's exit — the one place you leave for another title —
    /// and at two thirds the size of the posters you had just been scrolling
    /// through on Home it read as a footer rather than as somewhere to go. Passing
    /// the width explicitly rather than taking `PosterCard`'s default is what makes
    /// the card draw itself large: the default is `Theme.Art.posterWidth` (140), the
    /// library grid's tile, and everything the card scales — corner, label, badge —
    /// keys off the width it is handed.
    ///
    /// Titled "Related" rather than "More like this": it is what the TV app calls
    /// the same row, and it is the shorter and the more honest claim — the
    /// server's similarity answer is often a shared genre rather than a
    /// resemblance.
    func similarShelf(_ entries: [LibraryEntry], model: DetailModel) -> some View {
        DetailShelf(title: "Related") {
            ForEach(entries) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    PosterCard(
                        entry: entry, serverURL: serverURL, pipeline: pipeline,
                        width: Theme.Art.shelfPosterWidth,
                        // See `relatedActions`. This shelf is where a mis-scraped
                        // title is most often *noticed*, and until now it was the
                        // one poster in the app you could not act on.
                        metadata: relatedActions(entry, model: model)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Collection

    @ViewBuilder
    func collectionBody(_ model: DetailModel) -> some View {
        if model.collectionShelves.isEmpty {
            Text("Nothing in this collection yet.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textMuted)
                .padding(.vertical, Theme.Space.xl)
                .detailMargin()
        } else {
            ForEach(model.collectionShelves) { shelf in
                collectionShelf(shelf, model: model)
            }
        }
    }

    private func collectionShelf(_ shelf: CollectionShelf, model: DetailModel) -> some View {
        DetailShelf(title: shelf.title) {
            ForEach(shelf.entries) { entry in
                NavigationLink(value: DetailRoute.forEntry(entry)) {
                    PosterCard(
                        entry: entry, serverURL: serverURL, pipeline: pipeline,
                        width: Theme.Art.shelfPosterWidth
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    // The same commands a poster carries anywhere else. A
                    // collection is exactly where a wrong title or a missing
                    // poster is most visible and, until now, the one place it
                    // could not be fixed without leaving.
                    if app?.client != nil {
                        Button("Edit Metadata…") { editingId = entry.id }
                        Button("Choose or Remove Artwork…") { collectionArtworkId = entry.id }
                        Button("Refresh Metadata") {
                            Task {
                                await app?.refreshMetadata(
                                    itemId: entry.id, replaceEverything: false
                                )
                                await model.load()
                            }
                        }
                        Divider()
                    }
                    // The same command every other tile in the app now carries, so a
                    // collection is not the one place you have to open a title just
                    // to tick it off. Withheld from anything with no watch state —
                    // see `LibraryEntry.supportsWatchState`.
                    if entry.supportsWatchState {
                        Button(entry.isPlayed ? "Mark as Unwatched" : "Mark as Watched") {
                            Task { await model.setMemberWatched(entry) }
                        }
                        Divider()
                    }
                    // Only in the personal order. Offering "move left" in release
                    // order would promise something it cannot keep: the next
                    // recompute puts the row back where the years say it goes.
                    if model.collectionSort == .personal {
                        Button("Move Left") {
                            Task { await model.nudgeInCollection(memberId: entry.id, by: -1) }
                        }
                        Button("Move Right") {
                            Task { await model.nudgeInCollection(memberId: entry.id, by: 1) }
                        }
                        Button("Set Position…") {
                            positionEntry = entry
                            positionText = String(model.position(of: entry.id))
                        }
                        Divider()
                    }
                    Button("Move to Shelf…") { relabelingEntry = entry }
                    Divider()
                    Button("Remove from Collection…", role: .destructive) {
                        // Confirmed, like deleting the collection itself. This
                        // writes to the server and every other client sees it,
                        // and it fired on click.
                        removingFromCollection = entry
                    }
                }
            }
        }
    }
}
