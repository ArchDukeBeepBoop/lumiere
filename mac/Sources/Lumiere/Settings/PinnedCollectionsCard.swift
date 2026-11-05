import SwiftUI
import LumiereKit

/// Settings › Home › Collections on Home: the collections pinned with the pin
/// on a collection's page, each a row on Home under "Your Collections".
struct PinnedCollectionsCard: View {
    @State private var pinned = PinnedCollectionRows.pinned

    var body: some View {
        SettingsCard(title: "Collections on Home", icon: "pin", subtitle: "Each one its own row") {
            if pinned.isEmpty {
                SettingsNote("None yet. Open a collection and press the pin beside Mark Watched — a smart collection like Highly Rated, Not Yet Watched works well.")
            }
            ForEach(pinned, id: \.id) { pin in
                HStack {
                    Text(pin.name)
                    Spacer()
                    Button("Remove") {
                        PinnedCollectionRows.toggle(pin.id, name: pin.name)
                        pinned = PinnedCollectionRows.pinned
                    }
                }
            }
        }
        .onAppear { pinned = PinnedCollectionRows.pinned }
    }
}
