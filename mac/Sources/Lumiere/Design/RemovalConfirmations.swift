import SwiftUI
import LumiereKit

/// The two questions before content leaves the library, asked by the window.
///
/// They used to be a pair of dialogs on every card, and on Home — cards in
/// lazy shelves, re-made as they scroll — the dialog never appeared: "Delete
/// File…" did nothing at all, and no request ever reached the server. A card
/// now hands the question to this, and the shell shows the one dialog.
@MainActor
@Observable
final class RemovalCenter {
    static let shared = RemovalCenter()

    struct Pending: Identifiable {
        let title: String
        let permanent: Bool
        let perform: () async -> Void
        let id = UUID()
    }

    var pending: Pending?

    func ask(_ title: String, permanent: Bool, perform: @escaping () async -> Void) {
        pending = Pending(title: title, permanent: permanent, perform: perform)
    }
}

extension View {
    /// The window's one removal dialog. Attached by `ShellView`.
    func removalCenterDialog() -> some View {
        modifier(RemovalCenterDialog())
    }
}

private struct RemovalCenterDialog: ViewModifier {
    @Bindable private var center = RemovalCenter.shared

    func body(content: Content) -> some View {
        let current = center.pending
        content.confirmationDialog(
            current.map { $0.permanent ? "Move \($0.title) to the Trash?" : "Remove \($0.title) from the library?" } ?? "",
            isPresented: Binding(get: { center.pending != nil }, set: { if !$0 { center.pending = nil } }),
            titleVisibility: .visible
        ) {
            if let current {
                Button(current.permanent ? "Move to Trash" : "Remove", role: current.permanent ? .destructive : nil) {
                    center.pending = nil
                    Task { await current.perform() }
                }
            }
            Button("Cancel", role: .cancel) { center.pending = nil }
        } message: {
            if current?.permanent == true {
                Text("The files go to the Trash on their own drive, and the "
                   + "title leaves the library along with any seasons and "
                   + "episodes under it. Watch history for it is discarded. "
                   + "Recover the files from the Trash while it is there.")
            } else {
                Text("The files stay where they are. A show takes its seasons "
                   + "and episodes with it. Put it back any time from "
                   + "Settings › Library › Removed Items.")
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
