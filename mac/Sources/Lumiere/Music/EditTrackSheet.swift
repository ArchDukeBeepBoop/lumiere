import SwiftUI
import LumiereKit

/// Editing a track's tags, and the lyrics that go with it.
///
/// Its own sheet rather than the film editor with different labels, because the
/// fields that matter are different ones. A track has no synopsis and no original
/// title; it has an album, an album artist and a track number, and those three are
/// exactly what goes wrong on a badly-tagged rip — the album name groups the tracks,
/// the album artist groups the albums, and the number is the only thing that puts
/// them back in order. A compilation tagged with twelve different album artists
/// arrives as twelve one-track albums, which is the failure people actually hit.
struct EditTrackSheet: View {
    let itemId: String
    let repository: LibraryRepository
    let client: JellyfinClient
    let onDone: (Bool) -> Void

    @State private var name = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var artists = ""
    @State private var trackNumber = ""
    @State private var discNumber = ""
    @State private var year = ""
    @State private var genres = ""
    @State private var lyrics = ""
    @State private var originalLyrics = ""
    @State private var lyricsSupported = true
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        tags
                        lyricsCard
                    }
                }
            }

            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(Theme.Space.lg)
        .frame(width: 540, height: 620)
        .background(Theme.Palette.canvas)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Text("Edit Track")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button("Cancel") { onDone(false) }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var tags: some View {
        SettingsCard(title: "Tags", icon: "music.note") {
            field("Title", $name)
            field("Album", $album)
            field("Album artist", $albumArtist)
            SettingsNote("What groups the album on an artist page. A compilation "
                       + "tagged with a different album artist per track arrives as "
                       + "a dozen one-track albums — this is the field that fixes it.")

            field("Artists", $artists)
            SettingsNote("Performers on this track, separated by semicolons. A guest "
                       + "vocal belongs here rather than in album artist.")

            HStack(spacing: Theme.Space.md) {
                field("Track", $trackNumber, width: 70)
                field("Disc", $discNumber, width: 70)
                field("Year", $year, width: 90)
            }
            field("Genres", $genres)
        }
    }

    private var lyricsCard: some View {
        SettingsCard(
            title: "Lyrics",
            icon: "text.quote",
            subtitle: lyricsSupported ? "Stored on the server, with the track" : nil
        ) {
            if lyricsSupported {
                TextEditor(text: $lyrics)
                    .font(Theme.Font.body)
                    .frame(height: 150)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Space.xs)
                    .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: 6))
                SettingsNote("Paste in lyrics you already have. Lumiere does not fetch "
                           + "them — they go to the server as a file beside the track, "
                           + "so every client sees them.")
            } else {
                SettingsNote("This server has no lyrics endpoint. It arrived in "
                           + "a current server; on an older one the tags above still "
                           + "save normally.")
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || isLoading)
        }
    }

    private func field(
        _ label: String, _ text: Binding<String>, width: CGFloat? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: width == nil ? 110 : 50, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
            if width == nil { Spacer(minLength: 0) }
        }
    }

    // MARK: - Loading and saving

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let item = try? await client.item(id: itemId) else {
            message = "Couldn't read this track from the server."
            return
        }
        name = item.name
        year = item.productionYear.map(String.init) ?? ""
        trackNumber = item.indexNumber.map(String.init) ?? ""
        discNumber = item.parentIndexNumber.map(String.init) ?? ""
        genres = (item.genres ?? []).joined(separator: "; ")
        // Album and artists are not on the narrow model this app decodes; the
        // server holds them and the edit only writes what was typed, so leaving
        // these blank means "unchanged" rather than "cleared".
        album = ""
        albumArtist = ""
        artists = ""

        let fetched = try? await client.lyrics(itemId: itemId)
        lyricsSupported = true
        lyrics = fetched ?? ""
        originalLyrics = lyrics
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        message = nil

        let edit = ItemEdit(
            name: name,
            productionYear: Int(year.trimmingCharacters(in: .whitespaces)),
            album: album,
            albumArtist: albumArtist,
            artists: split(artists),
            trackNumber: Int(trackNumber.trimmingCharacters(in: .whitespaces)),
            discNumber: Int(discNumber.trimmingCharacters(in: .whitespaces)),
            genres: split(genres),
            // Name only. Genres on a track are frequently wrong *and* frequently
            // re-scraped into something better, so locking them would freeze a bad
            // guess; a title someone typed is the thing worth protecting.
            lockedFields: [.name]
        )

        do {
            try await client.updateItem(itemId: itemId, edit: edit)
            if lyrics != originalLyrics, !lyrics.isEmpty {
                do {
                    try await client.uploadLyrics(itemId: itemId, text: lyrics)
                } catch {
                    // Saved tags, failed lyrics. Reported rather than swallowed,
                    // and rather than failing the whole save — the tags did land.
                    message = "Tags saved. Lyrics were not: \(ConnectionState.message(for: error))"
                    lyricsSupported = false
                    return
                }
            }
            try? await repository.refreshItem(itemId: itemId)
            onDone(true)
        } catch JellyfinError.unauthorized {
            message = "Your account cannot edit items. Editing tags needs an "
                    + "administrator account on the server."
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    /// Semicolons, because a comma is inside plenty of artist names.
    private func split(_ value: String) -> [String]? {
        let parts = value
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }
}
