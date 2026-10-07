import SwiftUI
import LumiereKit

/// The two questions before content leaves the library.
struct RemovalConfirmations: ViewModifier {
    let actions: MetadataActions
    @Binding var confirmingRemove: Bool
    @Binding var confirmingDelete: Bool

    func body(content: Content) -> some View {
        if actions.removeFromLibrary == nil && actions.deleteToTrash == nil {
            content
        } else {
            content
                .confirmationDialog(
                    "Remove \(actions.title) from the library?",
                    isPresented: $confirmingRemove, titleVisibility: .visible
                ) {
                    Button("Remove") { Task { await actions.removeFromLibrary?() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The files stay where they are. A show takes its seasons "
                       + "and episodes with it. Put it back any time from "
                       + "Settings › Library › Removed Items.")
                }
                .confirmationDialog(
                    "Move \(actions.title) to the Trash?",
                    isPresented: $confirmingDelete, titleVisibility: .visible
                ) {
                    Button("Move to Trash", role: .destructive) {
                        Task { await actions.deleteToTrash?() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The files go to the Trash on their own drive, and the "
                       + "title leaves the library along with any seasons and "
                       + "episodes under it. Watch history for it is discarded. "
                       + "Recover the files from the Trash while it is there.")
                }
        }
    }
}


/// The same two questions, for a surface that keeps its own menu.
///
/// The episode strip and the music browser do not build `MetadataActions`,
/// so they cannot use the modifier above. This is the same dialog copy on a
/// binding, so the words a person reads before a file goes to the Trash are
/// the same words everywhere.
struct RemovalTarget: Identifiable {
    let entry: LibraryEntry
    let permanent: Bool
    var id: String { entry.id + (permanent ? ":trash" : ":remove") }
}

extension View {
    func removalConfirmations(
        target: Binding<RemovalTarget?>, perform: @escaping (RemovalTarget) async -> Void
    ) -> some View {
        confirmationDialog(
            target.wrappedValue.map {
                $0.permanent
                    ? "Move \($0.entry.item.name) to the Trash?"
                    : "Remove \($0.entry.item.name) from the library?"
            } ?? "",
            isPresented: Binding(
                get: { target.wrappedValue != nil },
                set: { if !$0 { target.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let current = target.wrappedValue {
                Button(current.permanent ? "Move to Trash" : "Remove",
                       role: current.permanent ? .destructive : nil) {
                    Task { await perform(current) }
                    target.wrappedValue = nil
                }
            }
            Button("Cancel", role: .cancel) { target.wrappedValue = nil }
        } message: {
            if target.wrappedValue?.permanent == true {
                Text("The file goes to the Trash on its own drive and the episode "
                   + "leaves the library. Its watch history is discarded.")
            } else {
                Text("The file stays where it is. Put it back any time from "
                   + "Settings › Library › Removed Items.")
            }
        }
    }
}
