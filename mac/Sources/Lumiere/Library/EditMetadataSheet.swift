import SwiftUI
import LumiereKit

/// Edits an item's metadata on the server, and locks it so a refresh cannot undo it.
///
/// Written around the case that makes it necessary: an anime matched against its
/// Japanese listing arrives in katakana, and renaming it without a lock lasts only
/// until the next scrape. So locking is not an advanced option tucked behind a
/// disclosure — it is on by default, and the sheet says what it protects and what it
/// cannot.
struct EditMetadataSheet: View {
    let itemId: String
    let repository: LibraryRepository
    let client: JellyfinClient
    let onDone: (Bool) -> Void

    @State private var name = ""
    @State private var originalTitle = ""
    @State private var sortName = ""
    /// What the server had, so a save can tell an edit from an untouched field.
    @State private var loadedSortName = ""
    @State private var overview = ""
    @State private var year = ""
    @State private var locksEditedFields = true
    @State private var locksEverything = false
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
                        fields
                        locking
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
        .frame(width: 520, height: 580)
        .background(Theme.Palette.canvas)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Text("Edit Metadata")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button("Cancel") { onDone(false) }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var fields: some View {
        SettingsCard(title: "Title", icon: "textformat") {
            labelled("Name") { TextField("", text: $name) }
            SettingsNote("What the app and every other client shows. This is the one "
                       + "a katakana match gets wrong.")

            labelled("Original title") { TextField("", text: $originalTitle) }
            SettingsNote("Kept separately by the server, so the Japanese title can stay "
                       + "on record while the name above reads in romaji.")

            labelled("Sort as") { TextField("", text: $sortName) }
            SettingsNote("What it files under. Without this, a renamed show stays "
                       + "alphabetised beside its old first letter.")

            labelled("Year") {
                TextField("", text: $year)
                    .frame(width: 90)
            }
        }

        SettingsCard(title: "Overview", icon: "text.alignleft") {
            TextEditor(text: $overview)
                .font(Theme.Font.body)
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.xs)
                .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: 6))
        }
    }

    private var locking: some View {
        SettingsCard(
            title: "Keep these changes",
            icon: "lock",
            subtitle: "Otherwise the next refresh overwrites them"
        ) {
            Toggle("Lock the fields I changed", isOn: $locksEditedFields)
            SettingsNote("The server will leave the name and overview alone on every "
                       + "future scrape, from any client — including this app's own "
                       + "Refresh and Replace All.")

            Toggle("Lock everything about this item", isOn: $locksEverything)
            // Said plainly because it is the part that surprises people: Jellyfin has
            // no per-field lock for sort name, year or premiere date. The whole-item
            // lock is the only thing that holds them.
            SettingsNote("Sort name and year have no lock of their own — the server only "
                       + "offers per-field locks for name, overview, genres, studios, "
                       + "tags, cast, runtime and rating. Locking the whole item is the "
                       + "only way to hold the rest, at the cost of never picking up "
                       + "new artwork or cast from a provider again.")
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

    private func labelled(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 110, alignment: .leading)
            control()
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Loading and saving

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // The server's copy rather than the cache's: the cache holds a narrow
        // subset, and an editor that shows less than it saves is a trap.
        guard let item = try? await client.item(id: itemId) else {
            message = "Couldn't read this item from the server."
            return
        }
        name = item.name
        overview = item.overview ?? ""
        year = item.productionYear.map(String.init) ?? ""
        originalTitle = item.originalTitle ?? ""
        sortName = item.sortName ?? ""
        loadedSortName = sortName
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        message = nil

        var locked: Set<ItemEdit.Lockable> = []
        if locksEditedFields {
            if !name.trimmingCharacters(in: .whitespaces).isEmpty { locked.insert(.name) }
            if !overview.trimmingCharacters(in: .whitespaces).isEmpty { locked.insert(.overview) }
        }

        let edit = ItemEdit(
            name: name,
            originalTitle: originalTitle,
            sortName: sortName,
            // Only when you actually changed it. This field is prefilled from the
            // server's computed sort name, so forcing it on every save turned an
            // automatic value into a permanent override for every item ever opened
            // in this sheet.
            forcesSortName: sortName != loadedSortName,
            overview: overview,
            productionYear: Int(year.trimmingCharacters(in: .whitespaces)),
            lockedFields: locked,
            lockAll: locksEverything
        )

        do {
            try await client.updateItem(itemId: itemId, edit: edit)
            // Read straight back so the change shows here without waiting for a
            // sync. Unlike a scrape this is synchronous on the server, so there is
            // nothing to wait out first.
            try? await repository.refreshItem(itemId: itemId)
            onDone(true)
        } catch JellyfinError.unauthorized {
            // Named rather than generic, because no amount of retrying fixes it.
            message = "Your account cannot edit items. Editing metadata "
                    + "needs an administrator account on the server."
        } catch {
            message = ConnectionState.message(for: error)
        }
    }
}
