import SwiftUI
import LumiereKit

/// What each library's shelf is allowed to draw from. See `ShelfRules`.
///
/// One library at a time, chosen from a picker, because a rule set is a small
/// form and nine of them stacked is a wall. The picker's default is the first
/// library with rules already set, so reopening Settings lands on what was
/// being edited.
struct ShelfRulesCard: View {
    @Bindable var app: AppModel
    @AppStorage(ShelfRules.storageKey) private var stored = ""
    @State private var libraryId = ""
    @State private var folderText = ""

    private var candidates: [LibraryRecord] {
        app.libraries.filter(\.holdsPlayableVideo)
    }

    private var all: [String: ShelfRules] { ShelfRules.all(from: stored) }
    private var rules: ShelfRules { ShelfRules.rules(for: libraryId, in: all) }

    var body: some View {
        SettingsCard(
            title: "Shelf Contents",
            icon: "line.3.horizontal.decrease.circle",
            subtitle: "What qualifies for a library's Latest row and for Recently Added"
        ) {
            if candidates.isEmpty {
                SettingsNote("No libraries yet.")
            } else {
                Picker("Library", selection: $libraryId) {
                    ForEach(candidates) { library in
                        Text(library.name + (all[library.id] == nil ? "" : " ·")).tag(library.id)
                    }
                }
                .onChange(of: libraryId) { folderText = rules.excludedFolders.joined(separator: ", ") }

                Divider().padding(.vertical, Theme.Space.xs)

                Text("Counts as content")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                Toggle("Films", isOn: binding(\.films))
                Toggle("Series", isOn: binding(\.series))
                Toggle("Episodes", isOn: binding(\.episodes))
                Toggle("Collections", isOn: binding(\.collections))
                Toggle("Loose videos", isOn: binding(\.videos))

                Divider().padding(.vertical, Theme.Space.xs)

                TextField("Folders to leave out", text: $folderText, prompt: Text("Samples, Extras, Behind the Scenes"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitFolders() }
                    .onChange(of: folderText) { commitFolders() }
                SettingsNote("Folder names, separated by commas. Anything inside a "
                           + "folder of that name — at any depth — stays off the shelf. "
                           + "Names rather than paths, so the rule survives a move.")

                Stepper(
                    "Shorter than \(rules.minimumMinutes) min is not content",
                    value: binding(\.minimumMinutes), in: 0...120, step: 5
                )
                SettingsNote("Zero is no rule. Files with no known length are never "
                           + "excluded by this.")

                if all[libraryId] != nil {
                    Button("Reset this library") {
                        var next = all
                        next[libraryId] = nil
                        stored = ShelfRules.encode(next)
                        folderText = ""
                        Task { await app.homeModel?.refresh("shelf rules") }
                    }
                    .font(Theme.Font.caption)
                }
            }

            SettingsNote("These rules decide what appears on the home screen. The "
                       + "library's own page still lists everything in it.")
        }
        .task {
            if libraryId.isEmpty {
                libraryId = candidates.first { all[$0.id] != nil }?.id ?? candidates.first?.id ?? ""
                folderText = rules.excludedFolders.joined(separator: ", ")
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ShelfRules, Value>) -> Binding<Value> {
        Binding(
            get: { rules[keyPath: keyPath] },
            set: { value in
                var next = all
                var updated = rules
                updated[keyPath: keyPath] = value
                next[libraryId] = updated == .default ? nil : updated
                stored = ShelfRules.encode(next)
                Task { await app.homeModel?.refresh("shelf rules") }
            }
        )
    }

    private func commitFolders() {
        let folders = folderText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard folders != rules.excludedFolders else { return }
        binding(\.excludedFolders).wrappedValue = folders
    }
}
