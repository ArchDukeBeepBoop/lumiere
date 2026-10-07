import SwiftUI
import LumiereKit

/// Adding one track, or a batch of them, to a playlist.
///
/// The `MusicActions` view modifier that used to head this file is gone: nothing
/// applied it, and the music context menu is built by `MetadataContextMenu` with
/// the music-specific commands passed in. The sheet below is what was actually
/// being used.
struct AddToPlaylistSheet: View {
    let itemIds: [String]
    let itemName: String
    let repository: LibraryRepository
    let onDone: () -> Void

    @State private var playlists: [LibraryEntry] = []
    @State private var isLoading = true
    @State private var newName = ""
    @State private var isWorking = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            newPlaylistRow
            Divider()

            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if playlists.isEmpty {
                Text("No playlists yet — create one above.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 420, height: 480)
        .background(Theme.Palette.canvas)
        .task {
            playlists = (try? await repository.audioPlaylists()) ?? []
            isLoading = false
        }
    }

    private var header: some View {
        HStack {
            Text("Add \"\(itemName)\" to Playlist")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var newPlaylistRow: some View {
        HStack(spacing: Theme.Space.sm) {
            TextField("New playlist name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await createAndAdd() } }
            Button("Create") { Task { await createAndAdd() } }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xs) {
                ForEach(playlists) { playlist in
                    Button { Task { await add(to: playlist.id) } } label: {
                        HStack {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.Palette.accent)
                            Text(playlist.item.name)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Spacer()
                        }
                        .padding(Theme.Space.sm)
                        .background(Theme.Palette.surface, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
            }
        }
    }

    private func add(to playlistId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.addToPlaylist(playlistId: playlistId, itemIds: itemIds)
            onDone()
            dismiss()
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.createPlaylist(name: name, itemIds: itemIds)
            onDone()
            dismiss()
        } catch {
            message = ConnectionState.message(for: error)
        }
    }
}
