import SwiftUI
import AppKit
import LumiereKit

/// Folders on this Mac, added as libraries.
///
/// Lumiere without a server: point it at a folder and everything the app does
/// applies — browsing, filename titles, generated thumbnails, search, favourites,
/// watch state, resume, subtitle handling. See `LocalLibrary` for why those come
/// for free rather than being rebuilt.
struct LocalFoldersCard: View {
    let app: AppModel

    @State private var folders: [LibraryRecord] = []
    @State private var scanning: String?
    @State private var message: String?
    @State private var removing: LibraryRecord?

    var body: some View {
        SettingsCard(
            title: "Folders on This Mac",
            icon: "folder.badge.plus",
            subtitle: "Browsed and played without a server",
            accessory: {
                Button("Add Folder…") { chooseFolder() }
                    .font(Theme.Font.caption)
                    .disabled(scanning != nil)
            },
            content: { content }
        )
        .task { await reload() }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this folder")?",
            isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let target = removing else { return }
                removing = nil
                Task { await remove(target) }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Removes the folder from Lumiere and forgets what you watched in "
               + "it. Nothing on disk is touched — no file is moved, renamed or "
               + "deleted.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if folders.isEmpty {
            SettingsNote("No folders added. Choose one and it appears in the sidebar "
                       + "and on the home screen beside your server's libraries.")
        } else {
            ForEach(folders) { folder in
                folderRow(folder)
            }
        }

        if let scanning {
            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small)
                Text("Reading \(scanning)…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
        }

        SettingsNote("Files are read where they are: nothing is copied, and nothing "
                   + "leaves this Mac. A folder is re-read when you ask it to — new "
                   + "files appear then, and files you have deleted stop appearing.")

        if let message {
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func folderRow(_ folder: LibraryRecord) -> some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text("\(folder.itemCount ?? 0) file\((folder.itemCount ?? 0) == 1 ? "" : "s")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            Spacer(minLength: 0)
            Button("Rescan") { Task { await rescan(folder) } }
                .font(Theme.Font.caption)
                .disabled(scanning != nil)
            Button { removing = folder } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.danger)
            }
            .buttonStyle(.plain)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of video files."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await scan(url) }
    }

    /// Re-reads a folder from the path its rows already carry.
    ///
    /// Any row will do — every item under the library knows its own file — and the
    /// root is that path minus however deep the item sits. Simpler than storing the
    /// root a second time and letting the two disagree.
    private func rescan(_ folder: LibraryRecord) async {
        guard let repository = app.repository,
              let path = try? await repository.localRootPath(libraryId: folder.id) else {
            message = "That folder's location is no longer recorded. Add it again."
            return
        }
        await scan(URL(fileURLWithPath: path))
    }

    private func scan(_ url: URL) async {
        guard let repository = app.repository else {
            message = "Sign in once so Lumiere has somewhere to keep its index, or "
                    + "wait for the library to finish opening."
            return
        }
        scanning = url.lastPathComponent
        message = nil
        defer { scanning = nil }
        do {
            let summary = try await repository.scanLocalFolder(at: url)
            await app.loadCachedLibraries()
            message = summary.unreadable.isEmpty
                ? "\(summary.name): \(summary.fileCount) files."
                : "\(summary.name): \(summary.fileCount) files. "
                + "\(summary.unreadable.count) folders could not be read — an "
                + "unmounted drive is the usual reason."
        } catch {
            message = error.localizedDescription
        }
        await reload()
    }

    private func remove(_ folder: LibraryRecord) async {
        guard let repository = app.repository else { return }
        try? await repository.removeLocalLibrary(id: folder.id)
        await app.loadCachedLibraries()
        await reload()
    }

    private func reload() async {
        folders = (try? await app.repository?.localLibraries()) ?? []
    }
}
