import SwiftUI
import LumiereKit

/// Which libraries feed the Recently Added row on the home screen.
///
/// The defaults are a policy — folder libraries, private ones, and anything
/// named as adult stay out — and this card is where that policy is visible and
/// overridable per library. See `RecentlyAddedPolicy` for why each default is
/// what it is.
struct RecentlyAddedCard: View {
    @Bindable var app: AppModel
    @AppStorage(RecentlyAddedPolicy.storageKey) private var stored = ""

    private var candidates: [LibraryRecord] {
        app.libraries.filter(\.holdsPlayableVideo)
    }

    var body: some View {
        SettingsCard(
            title: "Recently Added",
            icon: "sparkles",
            subtitle: "Which libraries appear in the home screen's Recently Added row"
        ) {
            if candidates.isEmpty {
                SettingsNote("No libraries yet.")
            } else {
                ForEach(candidates) { library in
                    Toggle(isOn: binding(for: library)) {
                        HStack(spacing: Theme.Space.xs) {
                            Text(library.name)
                            if let why = defaultReason(library) {
                                Text(why)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textMuted)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            SettingsNote("Each library's own row still shows its newest titles. "
                       + "This only decides what the row that mixes every library "
                       + "together is allowed to draw from.")
        }
    }

    /// Why a library is off by default, so the tick reads as a decision rather
    /// than a mystery.
    private func defaultReason(_ library: LibraryRecord) -> String? {
        if library.collectionType == nil { return "folder" }
        if app.privateLibraryIds.contains(library.id) { return "private" }
        if RecentlyAddedPolicy.isAdult(library.name) { return "adult" }
        return nil
    }

    private func binding(for library: LibraryRecord) -> Binding<Bool> {
        Binding(
            get: {
                !RecentlyAddedPolicy.excluded(
                    libraries: [library],
                    privateIds: app.privateLibraryIds,
                    stored: stored
                ).contains(library.id)
            },
            set: { included in
                var choices = RecentlyAddedPolicy.choices(from: stored)
                choices[library.id] = included
                stored = RecentlyAddedPolicy.store(choices)
                Task { await app.homeModel?.refresh("recently added policy") }
            }
        )
    }
}
