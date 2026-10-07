import SwiftUI
import LumiereKit

/// "Part of the Alien series" on a film's page, with the one click that files
/// it — so collections fill in as the library is browsed rather than only
/// when someone thinks to run the suggestion scan.
struct CollectionNudge: View {
    let repository: LibraryRepository
    let itemId: String

    @State private var group: FranchiseGrouping.Group?
    @State private var done: String?
    @State private var isWorking = false
    @State private var failure: String?
    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Group {
            if let done {
                Label(done, systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.Palette.textMuted)
            } else if let group {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(Theme.Palette.textMuted)
                    Text(prompt(group))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Button(group.existingCollectionId == nil ? "Make Collection" : "Add") {
                        Task { await accept(group) }
                    }
                    .disabled(isWorking)
                    if let failure {
                        Text(failure).foregroundStyle(Theme.Palette.textMuted)
                    }
                }
            }
        }
        .font(Theme.Font.caption)
        .padding(.horizontal, Theme.Space.shelfInset)
        .task(id: itemId) { group = await repository.seriesSuggestion(for: itemId) }
    }

    private func prompt(_ group: FranchiseGrouping.Group) -> String {
        if group.existingCollectionId != nil {
            return "Belongs in \(group.name)"
        }
        let others = group.itemIds.count - 1
        return "Part of \(group.name) — with \(others) other title\(others == 1 ? "" : "s") here"
    }

    private func accept(_ group: FranchiseGrouping.Group) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.acceptSuggestion(group)
            app?.report(group.existingCollectionId == nil ? "Made \(group.name)." : "Added to \(group.name).") {
                if let id = group.existingCollectionId {
                    for member in group.itemIds {
                        try? await repository.removeFromCollection(collectionId: id, itemId: member)
                    }
                } else if let made = try? await repository.collectionNamed(group.name) {
                    try? await repository.deleteCollection(id: made, announce: false)
                }
                done = nil
                self.group = await repository.seriesSuggestion(for: itemId)
            }
            done = group.existingCollectionId == nil ? "Made \(group.name)" : "Added to \(group.name)"
        } catch {
            failure = ConnectionState.message(for: error)
        }
    }
}
