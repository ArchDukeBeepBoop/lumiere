import SwiftUI
import LumiereKit

/// Right-click menus for the two shelves that had none.
///
/// Both were the odd ones out. Every poster elsewhere in the app — home shelves,
/// the library grid, search, favourites, the folder browser — answers a right-click
/// with the same list, and these two did not: a season could only be given artwork
/// through a menu attached to the *picker*, and a Related poster could only be
/// opened. Wrong artwork on a related title was visible and unfixable in the one
/// place you were looking at it.
///
/// Split from DetailView.swift for the project's 300-line rule.
extension DetailView {

    /// What right-clicking a season poster offers.
    ///
    /// One of the two menus in the app not built from `EntryActionState`, and
    /// the reason is the id: every command here writes against the *season*,
    /// which is not the entry the page is showing. The shared builder is written
    /// around one entry and the sheets that entry opens; a season's artwork and
    /// edit sheets are the detail page's own, keyed to whichever of series,
    /// season, episode or collection was right-clicked. Adopting the shared
    /// state here would mean this page holding two sets of sheet state that must
    /// agree, which is more moving parts than the duplication costs.
    ///
    /// What it shares is what matters: the same labels, and the same rule that a
    /// command either does something or is absent.
    ///
    /// The commands are the season's own, not the series'. Jellyfin models a season
    /// as a real item, so marking one watched, re-scraping it or giving it a poster
    /// are all writes against that id — and marking a season played marks the
    /// episodes under it, which is the point of having the command at this level
    /// rather than twenty times over in the strip.
    func seasonActions(_ season: LibraryEntry, model: DetailModel) -> MetadataActions? {
        guard let app, app.client != nil else { return nil }
        return MetadataActions(
            itemId: season.id,
            title: season.item.name,
            refresh: { replaceEverything in
                await app.refreshMetadata(
                    itemId: season.id, replaceEverything: replaceEverything
                )
                await model.load()
            },
            // The only route to per-season artwork there has ever been. No season in
            // a real library arrives with a poster of its own.
            chooseArtwork: { collectionArtworkId = season.id },
            // A season can name its own show. That is what makes bundling
            // work: a related title filed as a season of a series folder gets
            // its own match, its own poster and its own stills, rather than
            // whatever season of the parent its number happens to point at.
            identify: { identifySeason = season },
            editMetadata: { editingId = season.id },
            // Missing until now, and the only level of a show that had no star: an
            // episode has one in its own row, the series has one in the header, and
            // the season between them had watched-state commands and nothing else.
            isFavourite: season.userData?.isFavorite ?? false,
            toggleFavourite: {
                await app.toggleFavourite(
                    itemId: season.id,
                    isFavourite: season.userData?.isFavorite ?? false
                )
                await model.load()
            },
            isWatched: season.isPlayed,
            toggleWatched: season.supportsWatchState ? {
                await app.changeWatchState(of: season, watched: !season.isPlayed) {
                    await app.repository?.setPlayed(
                        itemId: season.id, played: !season.isPlayed
                    )
                }
                await model.load()
            } : nil,
            // See `MetadataActions.markUnwatched`: a season part way through reads
            // as unwatched to the toggle, so clearing it needs its own command.
            markUnwatched: season.supportsWatchState
                && (season.isPlayed || season.userData?.isInProgress == true) ? {
                await app.changeWatchState(of: season, watched: false) {
                    await app.repository?.clearWatchState(itemId: season.id)
                }
                await model.load()
            } : nil,
            removeFromLibrary: !Preference.allowsRemoval.value ? nil : {
                if await app.repository?.removeFromLibrary(itemId: season.id) == true {
                    app.report("\(season.item.name) removed. Restore it from Settings › Library.")
                    await model.load()
                }
            },
            deleteToTrash: !Preference.allowsRemoval.value ? nil : {
                do {
                    try await app.repository?.deleteToTrash(itemId: season.id)
                    app.reportTrashed("\(season.item.name)")
                    await model.load()
                } catch {
                    app.report(ConnectionState.message(for: error))
                }
            }
        )
    }

    /// What right-clicking a Related poster offers.
    ///
    /// Deliberately shorter than a home shelf's menu, and every omission is a
    /// command this page has nowhere to put: there is no Identify sheet here, no
    /// Add to Playlist, and nothing to hide a title *from* — this shelf is derived
    /// from the server's similarity answer, not from a list anyone curates. The
    /// house rule is that a menu item either does something or is absent, so those
    /// stay absent rather than appearing and doing nothing.
    func relatedActions(_ entry: LibraryEntry, model: DetailModel) -> MetadataActions? {
        guard let app, app.client != nil else { return nil }
        return MetadataActions(
            itemId: entry.item.id,
            title: entry.item.name,
            refresh: { replaceEverything in
                await app.refreshMetadata(
                    itemId: entry.item.id, replaceEverything: replaceEverything
                )
                await model.load()
            },
            chooseArtwork: { collectionArtworkId = entry.item.id },
            editMetadata: { editingId = entry.item.id },
            isFavourite: entry.userData?.isFavorite ?? false,
            toggleFavourite: {
                await app.toggleFavourite(
                    itemId: entry.item.id,
                    isFavourite: entry.userData?.isFavorite ?? false
                )
                await model.load()
            },
            isWatched: entry.isPlayed,
            toggleWatched: entry.supportsWatchState ? {
                await app.repository?.setPlayed(
                    itemId: entry.item.id, played: !entry.isPlayed
                )
                await model.load()
            } : nil,
            // See `MetadataActions.markUnwatched`.
            markUnwatched: entry.supportsWatchState
                && (entry.isPlayed || entry.userData?.isInProgress == true) ? {
                await app.repository?.clearWatchState(itemId: entry.item.id)
                await model.load()
            } : nil
        )
    }
}
