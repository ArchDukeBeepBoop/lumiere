import SwiftUI
import LumiereKit

/// Attaches the artwork picker to any view that has a client.
///
/// One modifier rather than the same twenty lines in five files. That is not
/// tidiness: the picker is where artwork is *removed*, and three of the five
/// contexts that offered "Choose Artwork…" had wired it to an empty closure — the
/// menu item rendered, was clicked, and did nothing. A shared host makes adding the
/// command to a new surface one line, so the next surface gets the working version
/// rather than a plausible-looking stub.
struct ArtworkPickerHost: ViewModifier {
    @Binding var itemId: String?
    let client: JellyfinClient?
    /// Called when something was actually changed, so the caller can re-read.
    let onChanged: () -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { itemId != nil },
            set: { if !$0 { itemId = nil } }
        )) {
            if let id = itemId, let client {
                ArtworkPickerSheet(itemId: id, client: client) { changed in
                    itemId = nil
                    if changed { onChanged() }
                }
            }
        }
    }
}

extension View {
    func artworkPicker(
        itemId: Binding<String?>,
        client: JellyfinClient?,
        onChanged: @escaping () -> Void
    ) -> some View {
        modifier(ArtworkPickerHost(itemId: itemId, client: client, onChanged: onChanged))
    }
}
