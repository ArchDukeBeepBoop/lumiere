import SwiftUI
import AppKit
import LumiereKit

/// A new library: what to call it, what kind of thing it holds, and where it
/// is on disk. Several folders may feed one library — two drives of films are
/// still one Films.
struct AddLibraryForm: View {
    let app: AppModel
    var suggestedName = ""
    let onDone: (Bool) -> Void

    @State private var name = ""
    @State private var kind: LibraryKind = .movies
    @State private var paths: [String] = []
    @State private var isSaving = false
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            TextField("Library name", text: $name, prompt: Text(suggestedName.isEmpty ? "Name" : suggestedName))
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(LibraryKind.allCases) { option in kindTile(option) }
            }
            Text(kind.explanation).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.Palette.accent)
                        Text(path).font(Theme.Font.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { paths.removeAll { $0 == path } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(Theme.Palette.textMuted)
                    }
                }
                Button(paths.isEmpty ? "Choose Folders…" : "Add Another Folder…") { choose() }
            }

            if let message {
                Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.danger)
            }
            HStack {
                Button("Cancel") { onDone(false) }
                Spacer()
                Button(isSaving ? "Adding…" : "Add Library") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(paths.isEmpty || isSaving)
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func kindTile(_ option: LibraryKind) -> some View {
        let isOn = option == kind
        return Button { kind = option } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: option.icon).frame(width: 18)
                Text(option.title).font(Theme.Font.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.sm).padding(.vertical, 7)
            .foregroundStyle(isOn ? Theme.Palette.onAccent : Theme.Palette.textPrimary)
            .background(isOn ? Theme.Palette.accent : Theme.Palette.surfaceRaised,
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose the folders that hold this library’s files."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !paths.contains(url.path) { paths.append(url.path) }
        if name.isEmpty, let first = panel.urls.first { name = first.lastPathComponent }
    }

    private func save() async {
        guard let client = app.client else { return }
        isSaving = true
        defer { isSaving = false }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? (suggestedName.isEmpty ? kind.title : suggestedName) : name
        do {
            try await client.createLibrary(name: title, kind: kind, paths: paths)
            onDone(true)
        } catch {
            message = (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
        }
    }
}
