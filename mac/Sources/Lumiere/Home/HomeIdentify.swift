import SwiftUI
import LumiereKit

/// Identify, on the home screen.
///
/// The library grid and search have offered "Identify…" since it shipped; the
/// home shelves never did, so the one screen you are guaranteed to be looking at
/// — the one showing the wrongly-matched film with the wrong poster on Continue
/// Watching — was the one screen you could not correct it from. You had to know
/// to go and find the title in its library first.
///
/// Written once as a modifier rather than three times inline because there are
/// three home layouts and this is exactly the kind of block that gets added to
/// two of them: Compact has already lost its whole right-click menu once that
/// way, and Hero has lost Next Up. One implementation cannot drift.
struct HomeIdentifySheet: ViewModifier {
    @Binding var entry: LibraryEntry?
    var app: AppModel?
    /// Re-reads whatever the caller shows. Identifying rewrites the title, the
    /// artwork and the year on the server, so a shelf that is not reloaded keeps
    /// showing the wrong match it was just used to fix.
    let reload: () async -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $entry) { target in
            if let app, let client = app.client {
                // An episode is identified through the show it belongs to.
                //
                // Continue Watching is mostly episodes, and the thing that is
                // wrong when a resume card shows the wrong artwork is the *series*
                // match — Jellyfin scraped the folder as some other show, and
                // every episode under it inherited that. Offering to re-identify
                // one episode would leave the show wrong and the other twenty-five
                // episodes with it.
                let isEpisode = target.item.itemType == .episode
                let subjectId = (isEpisode ? target.item.seriesId : nil) ?? target.item.id
                let subjectName = (isEpisode ? target.item.seriesName : nil) ?? target.item.name
                IdentifySheet(
                    itemId: subjectId,
                    // From the show's folder where the path reaches it. An episode's
                    // path walks up past the season, which is what `PathTitleGuess`
                    // already does, so the seed names the programme rather than the
                    // file — and the fallback is the show's scraped name, not the
                    // episode's.
                    initialQuery: PathTitleGuess.query(
                        path: target.item.path,
                        isFolder: target.item.isFolder,
                        fallback: subjectName
                    ),
                    isSeries: isEpisode || target.item.itemType == .series,
                    client: client,
                    onDone: { changed in
                        entry = nil
                        guard changed else { return }
                        // Refresh first, then reload: the server scrapes the new
                        // match asynchronously, and re-reading the cache without
                        // asking for the refresh shows the old title straight back.
                        Task {
                            await app.refreshMetadata(
                                itemId: subjectId, replaceEverything: false
                            )
                            await reload()
                        }
                    }
                )
            }
        }
    }
}

extension View {
    /// Attaches the home screen's Identify sheet.
    func homeIdentifySheet(
        entry: Binding<LibraryEntry?>,
        app: AppModel?,
        reload: @escaping () async -> Void
    ) -> some View {
        modifier(HomeIdentifySheet(entry: entry, app: app, reload: reload))
    }
}
