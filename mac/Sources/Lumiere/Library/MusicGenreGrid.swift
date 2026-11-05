import SwiftUI
import LumiereKit

/// A music library's genres as artwork: each card one of the genre's albums,
/// picked afresh by the server each visit, with the genre's name across it —
/// Apple Music's browse tiles rather than a column of words.
struct MusicGenreGrid: View {
    let repository: LibraryRepository
    let libraryId: String
    let serverURL: URL
    let pipeline: ImagePipeline
    let onOpen: (MusicCard) -> Void
    @State private var genres: [MusicCard]?
    @State private var failure: String?
    @Environment(\.displayScale) private var scale

    private let minimumWidth: CGFloat = 220

    var body: some View {
        ScrollView {
            if let genres, genres.isEmpty {
                EmptyStateView(reason: .empty(
                    icon: "guitars",
                    title: "No genres yet",
                    detail: "Genres come from your songs' tags, read by the server's next scan."
                ))
            } else if let failure {
                Text(failure).font(Theme.Font.body).foregroundStyle(Theme.Palette.danger)
                    .padding(Theme.Space.xl)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: Theme.Space.lg)],
                      spacing: Theme.Space.lg) {
                ForEach(genres ?? []) { genre in
                    Button { onOpen(genre) } label: { card(genre) }
                        .buttonStyle(.plain)
                        .labelledHelp("Open \(genre.name)")
                }
            }
            .padding(Theme.Space.xl)
        }
        .task(id: libraryId) {
            do {
                genres = try await repository.genreCards(libraryId: libraryId)
                failure = nil
            } catch {
                failure = ConnectionState.message(for: error)
            }
        }
    }

    private func card(_ genre: MusicCard) -> some View {
        Theme.Palette.artworkPlaceholder
            .aspectRatio(Theme.Art.backdropAspect, contentMode: .fit)
            .overlay {
                if let id = genre.pictureId {
                    RemoteImage(
                        request: ImageRequest(serverURL: serverURL, itemId: id, kind: .primary, tag: genre.pictureTag,
                                              displayWidth: minimumWidth * 1.4, aspectRatio: 1, screenScale: scale),
                        pipeline: pipeline, carriesText: true
                    )
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, Theme.Palette.onArtworkStrong], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                Text(genre.name)
                    .font(Theme.Font.libraryTitle)
                    .foregroundStyle(Theme.Palette.onArtworkText)
                    .lineLimit(2)
                    .padding(Theme.Space.md)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
