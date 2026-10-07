import SwiftUI
import LumiereKit

/// Which libraries never show a frame from the episode on Continue Watching.
///
/// See `DiscreetArtPolicy` for the default and why. This is the same shape as
/// the Recently Added card beside it: a per-library tick, the reason for its
/// default shown in grey, and the choice remembered.
struct DiscreetArtCard: View {
    @Bindable var app: AppModel
    @AppStorage(DiscreetArtPolicy.storageKey) private var stored = ""

    private var candidates: [LibraryRecord] {
        app.libraries.filter(\.holdsPlayableVideo)
    }

    var body: some View {
        SettingsCard(
            title: "Continue Watching Artwork",
            icon: "photo.on.rectangle.angled",
            subtitle: "Libraries whose cards show the series' artwork, never a frame from the episode"
        ) {
            if candidates.isEmpty {
                SettingsNote("No libraries yet.")
            } else {
                ForEach(candidates) { library in
                    Toggle(isOn: binding(for: library)) {
                        HStack(spacing: Theme.Space.xs) {
                            Text(library.name)
                            if DiscreetArtPolicy.excludedByDefault(library) {
                                Text("adult")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textMuted)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            SettingsNote("A ticked library's wide cards use the show's backdrop, "
                       + "else its poster, and draw a plain card when it has "
                       + "neither. An unticked one shows the episode's own still "
                       + "where the server has one, which is the better picture "
                       + "for everything that is not this.")
        }
    }

    private func binding(for library: LibraryRecord) -> Binding<Bool> {
        Binding(
            get: {
                DiscreetArtPolicy.discreet(libraries: [library], stored: stored)
                    .contains(library.id)
            },
            set: { discreet in
                var choices = RecentlyAddedPolicy.choices(from: stored)
                choices[library.id] = discreet
                stored = RecentlyAddedPolicy.store(choices)
                // The environment set is rebuilt from the library list, and the
                // list has not changed — so re-read it to republish.
                Task { await app.loadCachedLibraries() }
            }
        )
    }
}
