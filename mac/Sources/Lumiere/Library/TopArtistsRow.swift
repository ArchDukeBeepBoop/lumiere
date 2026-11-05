import SwiftUI
import LumiereKit

/// Top 10 Artists, at the head of the Music page: round photos ranked as the
/// TV app's Top 10 rows are, each beside its number. Ranked by plays, then
/// by how many of their tracks the library holds — so it says something on
/// the first day and follows your listening after that.
struct TopArtistsRow: View {
    let repository: LibraryRepository
    let libraryId: String
    let serverURL: URL
    let pipeline: ImagePipeline
    let onOpen: (MusicCard) -> Void
    @State private var artists: [MusicCard] = []
    @AppStorage(Preference.ranksTopTen.name) private var ranked = Preference.ranksTopTen.defaultValue
    @Environment(\.displayScale) private var scale

    private let photo: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if !artists.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top 10 Artists")
                        .font(Theme.Font.shelfHeader)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("By plays, then by how much of each you have")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: Theme.Space.tileGap) {
                        ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                            Button { onOpen(artist) } label: {
                                if ranked {
                                    RankedCard(rank: index + 1) { card(artist) }
                                } else {
                                    card(artist)
                                }
                            }
                            .buttonStyle(.plain)
                            .labelledHelp("Open \(artist.name)")
                        }
                    }
                }
            }
        }
        .padding(.bottom, artists.isEmpty ? 0 : Theme.Space.xl)
        .task(id: libraryId) { artists = await repository.topArtists(libraryId: libraryId) }
    }

    private func card(_ artist: MusicCard) -> some View {
        VStack(spacing: Theme.Space.sm) {
            RemoteImage(request: picture(artist), pipeline: pipeline)
                .frame(width: photo, height: photo)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 0.5))
            Text(artist.name)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .frame(width: photo)
        }
    }

    private func picture(_ artist: MusicCard) -> ImageRequest? {
        guard let id = artist.pictureId else { return nil }
        return ImageRequest(serverURL: serverURL, itemId: id, kind: .primary, tag: artist.pictureTag,
                            displayWidth: photo, aspectRatio: 1, screenScale: scale)
    }
}
