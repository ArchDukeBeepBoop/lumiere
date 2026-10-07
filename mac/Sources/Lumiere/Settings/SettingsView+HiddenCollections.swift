import SwiftUI
import LumiereKit

/// The list of collections Lumiere is keeping out of sight, and the way back.
///
/// Its own card rather than a row in "Hidden from Shelves": that list is about
/// Continue Watching, and this one exists for a different reason entirely — the
/// server re-creating TMDB's film collections after every scan. Someone looking for
/// "why is Ant-Man Collection gone" should find an explanation, not a mixed list.
extension SettingsView {
    @ViewBuilder
    var hiddenCollectionsCard: some View {
        SettingsCard(
            title: "Hidden Collections",
            icon: "rectangle.stack.badge.minus",
            subtitle: "Collections kept out of Lumiere without deleting them",
            accessory: {
                if !hiddenCollections.isEmpty {
                    Button("Show All") { Task { await showAllCollections() } }
                        .font(Theme.Font.caption)
                }
            }
        ) {
            if hiddenCollections.isEmpty {
                caption("Nothing hidden. Right-click a collection and choose Hide to "
                      + "keep it out of Lumiere. Worth knowing: the server's TMDB "
                      + "scraper creates a collection for every film that belongs to "
                      + "one and re-creates them on each library scan, so deleting "
                      + "those on the server does not make them stay gone — hiding "
                      + "does.")
            } else {
                ForEach(hiddenCollections) { collection in
                    HStack {
                        Text(collection.name)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Button("Show") {
                            Task { await showCollection(collection.id) }
                        }
                        .font(Theme.Font.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task { await loadHiddenCollections() }
    }

    func loadHiddenCollections() async {
        guard let repository = app.repository else { return }
        hiddenCollections = (try? await repository.hiddenCollections()) ?? []
    }

    private func showCollection(_ id: String) async {
        guard let repository = app.repository else { return }
        try? await repository.unhideCollection(id: id)
        await loadHiddenCollections()
    }

    private func showAllCollections() async {
        guard let repository = app.repository else { return }
        try? await repository.clearHiddenCollections()
        await loadHiddenCollections()
    }
}
