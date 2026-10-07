import SwiftUI
import LumiereKit

/// What has been removed from the library and can come back — and the switch
/// that puts the two removal commands on every menu in the first place.
///
/// Removal is the one thing this app was built never to do. It is now a
/// choice, with the reversible half surfaced here so "Remove from Library"
/// is never a dead end: everything taken out this way is listed, with its
/// files untouched, until it is restored or deleted for good.
struct RemovedItemsCard: View {
    @Bindable var app: AppModel
    @AppStorage(Preference.allowsRemoval.name) private var allowsRemoval
        = Preference.allowsRemoval.defaultValue
    @State private var removed: [JellyfinClient.RemovedItem] = []
    @State private var isLoading = false
    @State private var busy: String?
    @State private var deleting: JellyfinClient.RemovedItem?

    var body: some View {
        SettingsCard(
            title: "Removed Items",
            icon: "trash",
            subtitle: "Taken out of the library, files untouched",
            accessory: {
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .labelledHelp("Refresh the list")
            }
        ) {
            Toggle("Offer Remove and Delete on right-click menus", isOn: $allowsRemoval)
            SettingsNote("Two commands, two meanings. Remove from Library keeps the "
                       + "files and lists the title here until you restore it. "
                       + "Delete File moves the files to the Trash on their own "
                       + "drive — never straight to nothing — and discards the "
                       + "title's watch history. A show takes its seasons and "
                       + "episodes either way.")

            Divider().padding(.vertical, Theme.Space.xs)

            if isLoading && removed.isEmpty {
                ProgressView().controlSize(.small)
            } else if removed.isEmpty {
                SettingsNote("Nothing removed. Anything you take out of the library "
                           + "with Remove from Library appears here.")
            } else {
                ForEach(removed) { item in
                    HStack(spacing: Theme.Space.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(detail(item))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textMuted)
                        }
                        Spacer(minLength: Theme.Space.md)
                        Button("Restore") { Task { await restore(item) } }
                            .disabled(busy != nil)
                        Button("Delete File…", role: .destructive) { deleting = item }
                            .disabled(busy != nil)
                    }
                    .font(Theme.Font.caption)
                }
            }
        }
        .task { await reload() }
        .confirmationDialog(
            "Move \(deleting?.name ?? "")'s files to the Trash?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = deleting { Task { await deleteForGood(item) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The files go to the Trash on their own drive. This cannot be "
               + "undone from here — recover them from the Trash while they are "
               + "there.")
        }
    }

    private func detail(_ item: JellyfinClient.RemovedItem) -> String {
        var parts = [item.type]
        if item.members > 1 { parts.append("\(item.members) items") }
        if let path = item.path, !path.isEmpty {
            parts.append((path as NSString).abbreviatingWithTildeInPath)
        }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        guard let client = app.client else { return }
        isLoading = true
        defer { isLoading = false }
        removed = (try? await client.removedItems()) ?? []
    }

    private func restore(_ item: JellyfinClient.RemovedItem) async {
        guard let repository = app.repository else { return }
        busy = item.id
        defer { busy = nil }
        do {
            try await repository.restore(itemId: item.id)
            app.report("\(item.name) restored.")
            await app.contentDidChange("after restore")
        } catch {
            app.report(ConnectionState.message(for: error))
        }
        await reload()
    }

    private func deleteForGood(_ item: JellyfinClient.RemovedItem) async {
        guard let client = app.client else { return }
        busy = item.id
        defer { busy = nil }
        do {
            // A removed row is restored first so the server can find its
            // files, then sent to the Trash in one act.
            try await client.restore(itemId: item.id)
            try await client.deleteToTrash(itemId: item.id)
            app.reportTrashed("\(item.name)")
        } catch {
            app.report(ConnectionState.message(for: error))
        }
        await reload()
    }
}
