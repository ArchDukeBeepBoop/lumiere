import SwiftUI
import LumiereKit

/// Collections by theme — Immortality, Time Loops, Cop Dramas — built on the
/// server from each title's keywords, room by room. Each theme is a switch;
/// your own are a name and the keywords that find them.
struct ThemeCollectionsCard: View {
    let app: AppModel
    @State private var themes: [CollectionTheme] = []
    @State private var newName = ""
    @State private var newKeywords = ""
    @State private var isBusy = false
    @State private var note: String?

    var body: some View {
        SettingsCard(title: "Theme Collections", icon: "sparkles.rectangle.stack",
                     subtitle: "Collections by what titles are about") {
            SettingsNote("Built from each title's keywords on The Movie Database, kept up to date every night, and made separately for the Private Room. A theme needs three titles before it appears.")
            ForEach($themes) { $theme in
                Toggle(isOn: $theme.enabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name)
                        Text("\(theme.count ?? 0) titles · \(theme.keywords.prefix(3).joined(separator: ", "))")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted).lineLimit(1)
                    }
                }
                .toggleStyle(.switch)
                .contextMenu {
                    if theme.custom {
                        Button("Remove Theme", role: .destructive) {
                            themes.removeAll { $0.id == theme.id }
                            Task { await save() }
                        }
                    }
                }
            }
            HStack {
                TextField("New theme, e.g. Heists in Space", text: $newName)
                TextField("Keywords, comma separated", text: $newKeywords)
                Button("Add") { add() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newKeywords.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                Button(isBusy ? "Building…" : "Save & Build Now") { Task { await save() } }
                    .disabled(isBusy)
                if let note { Text(note).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary) }
            }
        }
        .task { await load() }
    }

    private func load() async {
        themes = (try? await app.client?.collectionThemes()) ?? []
    }

    private func add() {
        let words = newKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        themes.append(CollectionTheme(name: newName.trimmingCharacters(in: .whitespaces), keywords: words))
        newName = ""
        newKeywords = ""
        Task { await save() }
    }

    private func save() async {
        guard let client = app.client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.saveCollectionThemes(themes)
            await load()
            note = "Built. Find them under Collections."
            app.startSync(userInitiated: true)
        } catch {
            note = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
