import SwiftUI
import LumiereKit

/// What the browser shows: a spinner, an explanation, a wall of covers, or a list.
///
/// Split from ServerBrowserView.swift for the project's 300-line rule.
extension ServerBrowserView {

    @ViewBuilder
    var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            // Distinct from empty on purpose: nothing here is cached, so an
            // unreachable server means "we could not ask", not "there is nothing".
            //
            // Two wordings, because the app now knows which case it is in. When it
            // is already in offline mode the request was never sent, and saying
            // "couldn't reach the server" would imply it tried and something went
            // wrong just now — it did not, and there is a reconnect probe running
            // that will bring this screen back on its own.
            if app?.isOffline == true {
                EmptyStateView(reason: .empty(
                    icon: "wifi.slash",
                    title: "Not available offline",
                    detail: "Music and playlists are read from the server as you browse "
                          + "rather than cached, so there is nothing to show until it is "
                          + "back. This will fill in when it reconnects."
                ))
            } else {
                EmptyStateView(reason: .empty(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't reach the server",
                    detail: "Music and playlists are read live rather than cached, so this "
                          + "needs the server awake."
                ))
            }
        } else if entries.isEmpty {
            EmptyStateView(reason: .empty(
                icon: "music.note.list",
                title: "No music here",
                detail: "This library has nothing in it yet. Music appears as "
                      + "your server finishes scanning it."
            ))
        } else if usesTileGrid {
            // Albums and artists are recognised by their covers, so they get a wall
            // of square tiles rather than a column of names.
            MusicTileGrid(
                entries: entries,
                pipeline: pipeline,
                serverURL: serverURL,
                loadChildren: { entry in
                    (try? await repository.musicChildren(of: entry)) ?? []
                },
                onPlayAudio: { tracks, index in onPlayAudio?(tracks, index) },
                onOpen: { entry in path.append((id: entry.item.id, name: entry.item.name, kind: entry.item.itemType)) },
                onReachedEnd: { entry in await loadMoreIfNeeded(currentItem: entry) },
                header: artistHeader,
                menu: { entry in musicMenu(for: entry) }
            )
        } else {
            // A reader wraps the list so the alphabet rail has something to scroll.
            ScrollViewReader { proxy in
                ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                            ForEach(rows) { item in
                                switch item {
                                case .item(let entry):
                                    selectable(entry)
                                        .id(entry.id)
                                        .task { await loadMoreIfNeeded(currentItem: entry) }
                                    Divider().padding(.leading, 68)
                                case .series(let id, let name, let episodes):
                                    seriesRow(id: id, name: name, episodes: episodes)
                                    Divider().padding(.leading, 68)
                                    if expandedSeries.contains(id) {
                                        ForEach(episodes) { episode in
                                            menued(row(episode, indented: true), for: episode)
                                            Divider().padding(.leading, 96)
                                        }
                                    }
                                }
                            }
                            } header: {
                                // Pinned, so the column names stay above the tracks
                                // they name however far the list is scrolled — the
                                // header is only useful while you can still see rows.
                                trackColumnHeader
                                    .background(Theme.Palette.canvas)
                            }
                        }
                    .padding(.vertical, Theme.Space.sm)

                    if entries.count < total {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, Theme.Space.lg)
                    }
                }
                // Overlaid: a track list must not become narrower the moment it
                // grows past thirty rows.
                .overlay(alignment: .trailing) {
                    // Every list here, not only tracks: an artist wall and a
                    // playlist of four hundred rows are just as long.
                    // Only in name order: a rail cannot point into a list sorted by
                    // album or by length. See `TrackSort.supportsAlphabetRail`.
                    if entries.count > 30, trackSort.supportsAlphabetRail {
                        AlphabetRail(
                            destinations: railDestinations,
                            proxy: proxy,
                            prepare: { await loadThrough(letter: $0) }
                        )
                    }
                }
            }
        }
    }

    /// The artist header, when this page is an artist's.
    ///
    /// `AnyView` because it is handed to the grid as an optional slot, and an
    /// optional `some View` is not a thing Swift will express. One erasure at the
    /// boundary is cheaper than a generic parameter threaded through the grid for
    /// the one caller that uses it.
    private var artistHeader: AnyView? {
        guard let artist = currentArtist else { return nil }
        return AnyView(
            ArtistHeader(
                artistId: artist.id,
                name: artist.name,
                serverURL: serverURL,
                pipeline: pipeline,
                albumCount: entries.filter { $0.item.itemType == .musicAlbum }.count,
                loadTracks: {
                    // Every track under the artist, in album order, which is what
                    // "play this artist" should hand the queue.
                    let page = try? await repository.serverItemsPage(
                        parentId: artist.id, types: [.audio],
                        sortBy: ["Album", "ParentIndexNumber", "IndexNumber"],
                        limit: 500
                    )
                    return page?.entries ?? []
                },
                onPlay: { tracks, shuffled in
                    // Through the same entry point a track row uses, so the queue is
                    // built one way. Shuffle is the model's, not a pre-shuffled
                    // array — otherwise turning it off later would not restore the
                    // album order it was given.
                    onPlayAudio?(tracks, 0)
                    // The model's own shuffle, not a pre-shuffled array: it keeps
                    // the album order as `originalQueue`, so turning shuffle off
                    // later restores it rather than leaving a scrambled queue.
                    if shuffled, let music = app?.music, !music.isShuffled {
                        music.toggleShuffle()
                    }
                }
            )
        )
    }
}
