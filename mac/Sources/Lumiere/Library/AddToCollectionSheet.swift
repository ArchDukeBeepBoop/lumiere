import SwiftUI
import LumiereKit

/// Add one item to a collection, from wherever it is being browsed — a right
/// click should be enough to file a title, without leaving the grid or shelf to
/// go build the collection first.
struct AddToCollectionSheet: View {
    let itemId: String
    /// Every item being added. Defaults to just `itemId`, so the single-poster
    /// callers are unchanged while a batch can hand over forty at once.
    var itemIds: [String] = []
    let itemName: String
    let repository: LibraryRepository
    let onDone: () -> Void

    @State private var errorMessage: String?
    @State private var collections: [LibraryEntry] = []
    @State private var isLoading = true
    @State private var newName = ""
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    private var targetIds: [String] { itemIds.isEmpty ? [itemId] : itemIds }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            errorLine
            header
            newCollectionRow
            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if collections.isEmpty {
                Text("No collections yet — create one above.")
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
            collections = (try? await repository.allCollections()) ?? []
            isLoading = false
        }
    }

    private var header: some View {
        HStack {
            Text("Add \"\(itemName)\" to Collection")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var newCollectionRow: some View {
        HStack(spacing: Theme.Space.sm) {
            TextField("New collection name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await createAndAdd() } }
            Button("Create") { Task { await createAndAdd() } }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        }
        .overlay(alignment: .bottomLeading) { EmptyView() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xs) {
                ForEach(collections) { collection in
                    Button { Task { await add(to: collection.id) } } label: {
                        HStack {
                            Text(collection.item.name)
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

    private func add(to collectionId: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.addToCollection(collectionId: collectionId, itemIds: targetIds)
            onDone()
            dismiss()
        } catch {
            // Stays open and says so. Dismissing on failure was indistinguishable
            // from succeeding: forty titles the user believed were in a collection
            // were not, and nothing on screen ever said otherwise.
            errorMessage = ConnectionState.message(for: error)
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await repository.createCollection(name: name, itemIds: targetIds)
            onDone()
            dismiss()
        } catch {
            errorMessage = ConnectionState.message(for: error)
        }
    }
}
