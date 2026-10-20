import SwiftUI
import LumiereKit

/// Your queue, at the top of the Up Next panel: what you chose to watch next,
/// each with a way out, and the ways to keep it — save it as a playlist — or
/// to load one you kept.
struct PlayerQueueSection: View {
    let model: PlayerModel
    let onPlay: (LibraryEntry) -> Void
    private var queue: PlayQueue { PlayQueue.shared }

    @State private var playlists: [LibraryEntry] = []
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                PlayerSectionLabel(queue.playlistName ?? "Your Queue")
                Menu {
                    if !queue.isEmpty {
                        Button("Save as Playlist…") { name = queue.playlistName ?? ""; isNaming = true }
                        Button("Clear Queue", role: .destructive) { queue.clear() }
                        Divider()
                    }
                    if playlists.isEmpty { Text("No playlists yet") }
                    ForEach(playlists) { playlist in
                        Button("Play \(playlist.item.name)") { Task { await play(playlist) } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.Palette.onPlayerChrome)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.trailing, Theme.Space.sm)
            }
            if queue.isEmpty {
                Text("Right-click any film or episode and choose Play Next or Add to Queue.")
                    .font(Theme.Font.playerDetail)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .padding(.horizontal, Theme.Space.sm)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(queue.entries) { entry in
                HStack(spacing: 0) {
                    PlayerPanelRow(title: entry.item.name, detail: nil,
                                   subtitle: entry.item.seriesName, selected: false) {
                        queue.remove(entry.id)
                        onPlay(entry)
                    }
                    Button { queue.remove(entry.id) } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .labelledHelp("Take out of the queue")
                }
            }
            Rectangle().fill(Theme.PlayerPalette.surfaceStroke).frame(height: 1)
                .padding(.vertical, Theme.Space.xs)
        }
        .task { playlists = (try? await model.repository.audioPlaylists()) ?? [] }
        .alert("Save the queue as a playlist", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Save") { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A playlist is kept on your server, so the phone and the TV can play it too.")
        }
    }

    private func save() async {
        let title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        _ = try? await model.repository.createPlaylist(name: title, itemIds: queue.entries.map(\.id))
        playlists = (try? await model.repository.audioPlaylists()) ?? playlists
    }

    private func play(_ playlist: LibraryEntry) async {
        let entries = (try? await model.repository.playlistEntries(id: playlist.id)) ?? []
        queue.load(entries, playlist: playlist.item.name)
        if let first = queue.takeNext(after: nil) { onPlay(first) }
    }
}
