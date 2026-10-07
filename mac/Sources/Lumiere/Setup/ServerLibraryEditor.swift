import SwiftUI
import AppKit
import LumiereKit

/// The server's libraries and the folders that fill them, editable in place.
///
/// One view for the first-run guide and for Settings, so what the guide set up
/// is exactly what Settings shows afterwards: each library, its kind, every
/// folder it reads, whether it lives in the Private Room.
struct ServerLibraryEditor: View {
    let app: AppModel
    /// The guide hides the room switch; it has a step of its own for that.
    var showsRoom = true

    @State private var libraries: [ServerLibrary] = []
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var message: String?
    @State private var removing: ServerLibrary?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if isLoading && libraries.isEmpty {
                ProgressView().controlSize(.small)
            } else if libraries.isEmpty && !isAdding {
                SettingsNote("No libraries yet. Add one and choose the folders that hold your films, shows or music — nothing in them is moved or changed.")
            }
            ForEach(libraries) { library in libraryRow(library) }
            if isAdding {
                AddLibraryForm(app: app, suggestedName: libraries.isEmpty ? "Films" : "",
                               onDone: { made in
                                   isAdding = false
                                   if made { Task { await changed() } }
                               })
            } else {
                Button { isAdding = true } label: { Label("Add Library…", systemImage: "plus") }
            }
            if let message {
                Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.danger)
            }
        }
        .task { await reload() }
        .confirmationDialog("Remove \(removing?.name ?? "this library")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Library", role: .destructive) {
                guard let target = removing else { return }
                removing = nil
                Task { await act { try await $0.removeLibrary(target.id) } }
            }
        } message: {
            Text("Lumiere forgets this library and what you watched in it. The files on disk are not touched.")
        }
    }

    private func libraryRow(_ library: ServerLibrary) -> some View {
        let kind = LibraryKind(rawValue: library.collectionType) ?? .folders
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                SettingsIconChip(kind.icon)
                VStack(alignment: .leading, spacing: 1) {
                    Text(library.name).font(Theme.Font.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("\(kind.title) · \(library.itemCount.formatted()) \(library.itemCount == 1 ? "item" : "items")")
                        .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                }
                Spacer(minLength: 0)
                Menu {
                    Picker("Kind", selection: Binding(get: { kind }, set: { new in
                        Task { await act { try await $0.updateLibrary(library.id, kind: new) } }
                    })) {
                        ForEach(LibraryKind.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Add Folder…") { chooseFolder(for: library) }
                    Divider()
                    Button("Remove Library…", role: .destructive) { removing = library }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            ForEach(library.folders) { folder in
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "folder").foregroundStyle(Theme.Palette.textMuted)
                    Text(folder.path).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        Task { await act { try await $0.removeLibraryFolder(library.id, folderId: folder.id) } }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Stop reading this folder. Nothing on disk changes.")
                }
                .padding(.leading, 40)
            }
            HStack {
                Button("Add Folder…") { chooseFolder(for: library) }.buttonStyle(.link)
                if showsRoom {
                    Spacer()
                    Toggle("In the Private Room", isOn: Binding(
                        get: { app.privateLibraryIds.contains(library.id) },
                        set: { on in
                            var ids = app.privateLibraryIds
                            if on { ids.insert(library.id) } else { ids.remove(library.id) }
                            app.privateLibraryIds = ids
                        }))
                    .toggleStyle(.switch).controlSize(.mini).font(Theme.Font.caption)
                }
            }
            .padding(.leading, 40)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func chooseFolder(for library: ServerLibrary) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to \(library.name)"
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        Task {
            await act { client in
                for path in paths { try await client.addLibraryFolder(library.id, path: path) }
            }
        }
    }

    private func act(_ change: @escaping (JellyfinClient) async throws -> Void) async {
        guard let client = app.client else { return }
        do {
            try await change(client)
            message = nil
        } catch {
            message = (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
        }
        await changed()
    }

    private func changed() async {
        await reload()
        app.startSync(userInitiated: true)
    }

    private func reload() async {
        defer { isLoading = false }
        guard let client = app.client else { return }
        if let list = try? await client.serverLibraries() { libraries = list }
    }
}
