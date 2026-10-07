import SwiftUI
import LumiereKit

/// Proposes collections for a library, and creates the ones you accept.
///
/// Review rather than automation, deliberately. Metadata grouping is a guess — a
/// good one, but a guess — and a scan that silently created forty collections on
/// the server would be far harder to undo than to approve. So every group arrives
/// switched off, named, counted, and carrying the metadata it was built from.
struct RelatedCollectionsSheet: View {
    let libraryId: String
    let libraryName: String
    let repository: LibraryRepository
    /// For the authoring step, which writes to the server. Without a client the
    /// scan still creates collections; it just cannot finish them.
    var client: JellyfinClient?
    var pipeline: ImagePipeline?
    var serverURL: URL?
    let onDone: (Bool) -> Void

    @State private var groups: [FranchiseGrouping.Group] = []
    @State private var accepted: Set<String> = []
    @Environment(AppModel.self) private var app: AppModel?
    @State private var scanned: (done: Int, total: Int)?
    @State private var isScanning = true
    @State private var isCreating = false
    @State private var message: String?
    /// The collections just created, handed to the authoring wizard.
    @State private var authoring: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header

            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
            }

            if isScanning {
                scanning
            } else if groups.isEmpty {
                empty
            } else {
                list
                footer
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 520, height: 560)
        .background(Theme.Palette.canvas)
        .task { await scan() }
        .sheet(isPresented: Binding(
            get: { !authoring.isEmpty },
            set: { if !$0 { authoring = [] } }
        )) {
            if let client, let pipeline, let serverURL {
                CollectionAuthoringSheet(
                    collectionIds: authoring,
                    repository: repository,
                    client: client,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    onDone: {
                        authoring = []
                        onDone(true)
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Related in \(libraryName)")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Grouped by shared tags and creators — not by title, so a "
                   + "franchise whose entries are named differently still holds "
                   + "together.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.md)
            Button("Cancel") { onDone(false) }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var scanning: some View {
        VStack(spacing: Theme.Space.sm) {
            ProgressView(
                value: Double(scanned?.done ?? 0),
                total: Double(max(1, scanned?.total ?? 1))
            )
            .tint(Theme.Palette.accent)
            Text(scanned.map { "Read \($0.done) of \($0.total)" } ?? "Asking the server…")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "rectangle.stack.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Palette.textDisabled)
            Text("Nothing related found")
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            // Says which metadata was missing rather than implying the library has
            // no franchises in it — on a library the server never scraped tags for,
            // there is nothing here to group by and that is worth knowing.
            Text("This groups on the tags and credits your server holds. If its "
               + "titles have neither, there is nothing to relate them by — a "
               + "metadata refresh on the library is what would change that.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xs) {
                ForEach(groups) { group in
                    Toggle(isOn: binding(for: group)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.existingCollectionId == nil ? group.name : "Add to \(group.name)")
                                .font(Theme.Font.cardTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text("\(group.itemIds.count) titles · \(group.reason)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textMuted)
                                .lineLimit(1)
                            if !group.missing.isEmpty {
                                Text("Missing: " + group.missing.joined(separator: ", "))
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(Theme.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.surface, in: .rect(cornerRadius: 8))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(accepted.count == groups.count ? "Select None" : "Select All") {
                accepted = accepted.count == groups.count ? [] : Set(groups.map(\.id))
            }
            .font(Theme.Font.caption)
            Spacer()
            Button(isCreating ? "Saving…" : "Apply \(accepted.count) Suggestions") {
                Task { await create() }
            }
            .disabled(accepted.isEmpty || isCreating)
        }
    }

    private func binding(for group: FranchiseGrouping.Group) -> Binding<Bool> {
        Binding(
            get: { accepted.contains(group.id) },
            set: { isOn in
                if isOn { accepted.insert(group.id) } else { accepted.remove(group.id) }
            }
        )
    }

    private func scan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            groups = try await repository.franchiseSuggestions(
                libraryId: libraryId,
                progress: { done, total in
                    Task { @MainActor in scanned = (done, total) }
                }
            )
            // Exact matches start ticked; guesses wait to be checked.
            accepted = Set(groups.filter(\.isStrong).map(\.id))
        } catch {
            message = ConnectionState.message(for: error)
            groups = []
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let chosen = groups.filter { accepted.contains($0.id) }
        do {
            let created = try await repository.createCollections(chosen)
            offerUndo(chosen, created: created)
            // Reported rather than assumed: a name already in use is skipped, so
            // "create 8" can legitimately produce 6, and silently doing so would
            // look like a failure.
            if created.count < chosen.count {
                // Only reachable by a name collision now: anything else throws and
                // is reported as itself by the catch below.
                message = "\(created.count) created. "
                        + "\(chosen.count - created.count) already existed by name."
                accepted = []
            }
            // Straight into naming them, because a collection called "monogatari"
            // with no year, no synopsis and no poster is the scan half-finished —
            // and finishing it by hand is the work this was meant to remove.
            // Only the new ones: a collection that was added to is already named.
            let existing = Set(chosen.compactMap(\.existingCollectionId))
            let fresh = created.filter { !existing.contains($0) }
            if !fresh.isEmpty, client != nil {
                authoring = fresh
            } else if created.count == chosen.count {
                onDone(true)
            }
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    /// One Undo for the whole batch: titles added to existing collections come
    /// out again, and collections this made are deleted.
    private func offerUndo(_ chosen: [FranchiseGrouping.Group], created: [String]) {
        let existing = Set(chosen.compactMap(\.existingCollectionId))
        let additions = chosen.filter { $0.existingCollectionId != nil }
        let made = created.filter { !existing.contains($0) }
        app?.report("Applied \(chosen.count) suggestions.") { [repository] in
            for group in additions {
                for member in group.itemIds {
                    try? await repository.removeFromCollection(collectionId: group.existingCollectionId!, itemId: member)
                }
            }
            for id in made { try? await repository.deleteCollection(id: id, announce: false) }
        }
    }
}
