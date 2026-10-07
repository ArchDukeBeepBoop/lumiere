import SwiftUI
import LumiereKit

/// The genre row, on every home layout.
///
/// A row rather than a sidebar section on purpose: browsing by genre is something
/// you do when you do not know what you want, and a list of words in the chrome
/// is the wrong shape for that — you have to read it to use it. On the home
/// screen, at the size of the artwork beside it, it is something you notice.
///
/// Built as an ordinary `Shelf` so it inherits the title card, the insets and the
/// hover room every other row has; the only thing different about it is what the
/// tiles are.
struct GenreShelf: View {
    let genres: [GenreCardItem]
    let serverURL: URL
    let pipeline: ImagePipeline

    var body: some View {
        if !genres.isEmpty {
            Shelf(
                title: "Browse by genre", subtitle: subtitle,
                itemCount: genres.count, itemWidth: Theme.Art.genreCardWidth
            ) {
                ForEach(genres) { genre in
                    NavigationLink(value: GenreRoute(name: genre.name)) {
                        GenreCard(genre: genre, serverURL: serverURL, pipeline: pipeline)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Named rather than counted: "10 genres" is a fact about this row, which is
    /// not the interesting number. What the line is for is saying that clicking a
    /// card goes somewhere.
    private var subtitle: String { "Everything in your library, by category" }
}
