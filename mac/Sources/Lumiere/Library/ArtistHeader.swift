import SwiftUI
import LumiereKit

/// An artist, presented as an artist rather than as a folder that happens to
/// contain albums.
///
/// Opening one used to give you the same wall of covers any directory gets: no
/// picture of the artist, no name at the top, and no way to play their work without
/// first choosing an album. Every music app answers "who is this and play them"
/// before it answers "what did they release", and that is all this is.
///
/// Deliberately not a Top Songs section. That needs play counts to rank by, and this
/// app does not sync music — the counts live on the server, and asking it for
/// tracks "by play count" on a library nobody has played through Jellyfin returns an
/// arbitrary order dressed up as a chart. A section that is sometimes meaningless is
/// worse than one that is absent.
struct ArtistHeader: View {
    let artistId: String
    let name: String
    let serverURL: URL
    let pipeline: ImagePipeline
    /// How many albums are on screen beneath this, for the subtitle.
    let albumCount: Int
    /// Fetches every track this artist has, for the two buttons.
    let loadTracks: () async -> [LibraryEntry]
    let onPlay: ([LibraryEntry], Bool) -> Void

    @State private var isWorking = false
    @Environment(\.displayScale) private var scale

    /// Square, and large enough to be a portrait rather than a thumbnail. An
    /// artist image is the one piece of music artwork that is not a cover, so
    /// borrowing the album tile's size would make the person look like a record.
    private var portrait: CGFloat { 160 }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            artwork
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(name)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                if albumCount > 0 {
                    Text("\(albumCount) album\(albumCount == 1 ? "" : "s")")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                buttons
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.lg)
    }

    private var artwork: some View {
        RemoteImage(
            request: ImageRequest(
                serverURL: serverURL, itemId: artistId, kind: .primary,
                // No tag: an artist's image is fetched by id, and the server answers
                // with whatever it has. A wrong tag would 404 into a blank square.
                tag: nil, displayWidth: portrait, aspectRatio: 1, screenScale: scale
            ),
            pipeline: pipeline
        )
        .frame(width: portrait, height: portrait)
        // A circle, which is how every music app draws a person and how nothing
        // draws an album — so the shape alone says which kind of page this is.
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Space.sm) {
            button("Play", icon: "play.fill", shuffled: false)
            button("Shuffle", icon: "shuffle", shuffled: true)
        }
        .padding(.top, Theme.Space.xs)
    }

    private func button(_ title: String, icon: String, shuffled: Bool) -> some View {
        Button {
            guard !isWorking else { return }
            isWorking = true
            Task {
                // Every track the artist has, not the album on screen. "Play" on an
                // artist means the artist.
                let tracks = await loadTracks()
                isWorking = false
                guard !tracks.isEmpty else { return }
                onPlay(tracks, shuffled)
            }
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.Font.body)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .background(Theme.Palette.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}
