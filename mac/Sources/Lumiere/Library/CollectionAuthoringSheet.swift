import SwiftUI
import LumiereKit

/// Walks a set of newly built collections through the details a scan cannot know.
///
/// The scan finds that eleven files belong together and calls the result
/// "Monogatari". That is the hard part solved and the visible part not: the
/// collection has no year, no synopsis and no poster, and fixing that by hand —
/// eleven times, across a dozen franchises — is the work this whole feature exists
/// to remove.
///
/// So this steps through them one at a time with everything pre-filled from the
/// members themselves, and every field editable before it is written. The writes go
/// to the server with the edited fields locked, because a collection whose name a
/// refresh can revert is a collection you will be naming again next month.
struct CollectionAuthoringSheet: View {
    /// The collections to walk, in the order they were created.
    let collectionIds: [String]
    let repository: LibraryRepository
    let client: JellyfinClient
    let pipeline: ImagePipeline
    let serverURL: URL
    let onDone: () -> Void

    @State private var index = 0
    // Not private: CollectionAuthoringSheet+Preview.swift draws from these, and
    // Swift's `private` is file-scoped.
    @State var entry: LibraryEntry?
    @State var members: [LibraryEntry] = []
    @State private var draft = CollectionDraft.Suggestion(
        name: "", year: nil, overview: "", overviewSource: nil
    )
    @State private var yearText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State var isChoosingArtwork = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var message: String?
    @Environment(\.displayScale) var scale

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        details
                        artwork
                        contents
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
        .frame(width: 560, height: 620)
        .background(Theme.Palette.canvas)
        .task(id: index) { await load() }
        .confirmationDialog(
            "Delete \(draft.name.isEmpty ? "this collection" : draft.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Says what survives, because "delete" beside a list of titles reads as
            // though it deletes the titles. A BoxSet is a grouping, not a folder.
            Text("Removes the collection from your server. The \(members.count) "
               + "titles in it are untouched — they live in their own libraries and "
               + "stay exactly where they are, with their watch history intact. "
               + "Nothing is deleted from disk.")
        }
        .sheet(isPresented: $isChoosingArtwork) {
            if let entry {
                ArtworkPickerSheet(itemId: entry.id, client: client) { changed in
                    isChoosingArtwork = false
                    if changed { Task { await load() } }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Finish Collection")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("\(index + 1) of \(collectionIds.count) · everything below is "
                   + "suggested from what the collection holds")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            Spacer(minLength: Theme.Space.md)
            Button("Close") { onDone() }
        }
    }

    private var details: some View {
        SettingsCard(title: "Details", icon: "textformat") {
            labelled("Name") { TextField("", text: $draft.name) }
            labelled("Year") { TextField("", text: $yearText).frame(width: 90) }
            SettingsNote(draft.year != nil
                ? "The earliest year among its titles — when the franchise started, "
                + "which is what a collection's date means."
                : "None of its titles carry a year, so this is blank rather than "
                + "guessed.")

            TextEditor(text: $draft.overview)
                .font(Theme.Font.body)
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.xs)
                .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: 6))

            // Says whose paragraph this is. Presenting a borrowed synopsis as the
            // collection's own reads badly the moment you notice it.
            if let source = draft.overviewSource {
                SettingsNote("Borrowed from \(source) — the earliest entry with a "
                           + "synopsis, since that describes the premise the rest is "
                           + "built on. Edit it freely; it is a starting point.")
            }
        }
    }

    private var footer: some View {
        HStack {
            // Deleting is the other real answer, and it belongs here rather than
            // three screens away: this is the moment you can see what the scan
            // actually grouped, and a wrong grouping should be removable at the
            // point you notice it rather than left on the server as litter.
            Button("Delete…") { isConfirmingDelete = true }
                .foregroundStyle(Theme.Palette.danger)
                .disabled(isSaving || isDeleting || isLoading)

            // Skipping keeps the collection and moves on, for one that is right but
            // that you would rather name later.
            Button("Skip") { advance() }
                .disabled(isSaving || isDeleting)
            Spacer()
            Button(isSaving ? "Saving…" : (isLast ? "Save & Finish" : "Save & Next")) {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving || isLoading)
        }
    }

    private var isLast: Bool { index >= collectionIds.count - 1 }

    /// A label column wide enough for both fields, so Name and Year line up rather
    /// than each finding its own left edge.
    private func labelled(
        _ label: String, @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 60, alignment: .leading)
            control()
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Loading and saving

    private func load() async {
        guard index < collectionIds.count else { onDone(); return }
        isLoading = true
        defer { isLoading = false }
        message = nil

        let id = collectionIds[index]
        entry = try? await repository.entry(id: id)
        members = (try? await repository.collectionItems(collectionId: id)) ?? []

        let suggestion = CollectionDraft.suggest(
            name: entry?.item.name ?? "Collection", members: members
        )
        draft = suggestion
        yearText = suggestion.year.map(String.init) ?? ""
    }

    private func save() async {
        guard index < collectionIds.count else { return }
        isSaving = true
        defer { isSaving = false }

        let edit = ItemEdit(
            name: draft.name,
            sortName: draft.name,
            overview: draft.overview,
            productionYear: Int(yearText.trimmingCharacters(in: .whitespaces)),
            // Locked, because this is the entire point. A collection whose name a
            // refresh can revert is one you will be naming again next month.
            lockedFields: [.name, .overview]
        )

        do {
            try await client.updateItem(itemId: collectionIds[index], edit: edit)
            try? await repository.refreshItem(itemId: collectionIds[index])
            advance()
        } catch JellyfinError.unauthorized {
            message = "Your account cannot edit items. Naming a collection "
                    + "needs an administrator account on the server."
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    private func delete() async {
        guard index < collectionIds.count else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await repository.deleteCollection(id: collectionIds[index])
            advance()
        } catch JellyfinError.unauthorized {
            // Named on its own, because Jellyfin gates deletion separately from
            // editing: an account that can rename this may still not delete it.
            message = "Your account cannot delete items. That permission is "
                    + "separate from editing, and is set per user on the server."
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    private func advance() {
        if isLast {
            onDone()
        } else {
            index += 1
        }
    }
}
