import SwiftUI
import LumiereKit

/// On This Computer: Lumiere as a player for whatever is on this Mac, with or
/// without the server.
///
/// One page that answers "what was I playing, and how do I play something
/// else": Continue for unfinished local files, Recent for what was opened,
/// Folders for the ones added in Settings, and the three ways in — a file, a
/// folder, an address. Browsing a folder is the folder browser every library
/// already uses; this page is the doorway to it, not a second browser.
struct ComputerView: View {
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    let app: AppModel
    let onOpenFolder: (LibraryRecord) -> Void

    @State private var resume: [LibraryEntry] = []
    @State private var upNext: [LibraryEntry] = []
    @State private var recents: [URL] = OpenRecents.all
    @State private var folders: [LibraryRecord] = []
    @State private var askingAddress = false
    @State private var isAddingFolder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.shelfGap) {
                header
                if !resume.isEmpty { shelf("Continue", resume) }
                if !upNext.isEmpty { shelf("Up Next", upNext) }
                ComputerRecentList(recents: recents, open: { app.open([$0]) })
                ComputerFolderList(
                    folders: folders, isAdding: isAddingFolder,
                    open: onOpenFolder, add: addFolder
                )
            }
            .padding(.vertical, Theme.Space.xxl)
        }
        .scrollContentBackground(.hidden)
        .task { await load() }
        .onLibraryChange { _ in await load() }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentsChanged)) { _ in
            recents = OpenRecents.all
        }
        .onReceive(NotificationCenter.default.publisher(for: .askOpenAddress)) { _ in askingAddress = true }
        .sheet(isPresented: $askingAddress) {
            OpenAddressSheet { app.open([$0]) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("On This Computer")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Play anything on this Mac, with or without the server. Drop files on the window or the Dock icon to play them.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: 560, alignment: .leading)
            HStack(spacing: Theme.Space.sm) {
                Button { app.chooseFilesToOpen() } label: {
                    Label("Open File…", systemImage: "doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
                Button { app.chooseFolderToOpen() } label: {
                    Label("Open Folder…", systemImage: "folder")
                }
                Button { askingAddress = true } label: {
                    Label("Open Address…", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .padding(.top, Theme.Space.xs)
        }
        .padding(.horizontal, Theme.Space.shelfInset)
    }

    /// A row of wide cards — Continue, then Up Next: the next file in each
    /// folder you've been watching. See `localUpNext`.
    private func shelf(_ title: String, _ entries: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ComputerSectionTitle(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.tileGap) {
                    ForEach(entries) { entry in
                        Button { app.nowPlayingItemId = entry.id } label: {
                            WideCard(
                                entry: entry, serverURL: serverURL, pipeline: pipeline,
                                width: Theme.Art.continueCardWidth,
                                onPlay: { app.nowPlayingItemId = entry.id }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.shelfInset)
            }
        }
    }

    private func load() async {
        resume = (try? await repository.resumeEntries(limit: 12, server: LocalLibrary.serverId)) ?? []
        upNext = (try? await repository.localUpNext()) ?? []
        folders = ((try? await repository.localLibraries()) ?? [])
            .filter { $0.id != LocalLibrary.openedLibraryId }
        recents = OpenRecents.all
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder to keep on this page. Lumiere reads it; nothing in it is changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isAddingFolder = true
        Task {
            defer { isAddingFolder = false }
            do {
                let summary = try await repository.scanLocalFolder(at: url)
                await app.loadCachedLibraries()
                await load()
                app.report("Added \(summary.name) — \(summary.fileCount) files.", actionTitle: "")
            } catch {
                app.report("Couldn’t read \(url.lastPathComponent): \(ConnectionState.message(for: error))", actionTitle: "")
            }
        }
    }
}

struct ComputerSectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.Font.shelfHeader)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Space.shelfInset)
    }
}
