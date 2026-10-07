import SwiftUI
import LumiereKit

/// "Another copy: The Long Quiet (2019) 1080p.mp4" under a film that exists
/// twice. The server files the two as separate titles, so the version picker
/// never saw the second; this says it is there and opens it. Nothing shows
/// for a film with one file, which is almost all of them.
struct OtherCopiesLine: View {
    let repository: LibraryRepository
    let entry: LibraryEntry
    @State private var copies: [LibraryEntry] = []
    /// The film after this one in its collection — "what now?" answered at
    /// the foot of the header rather than by going to look for it.
    @State private var next: (entry: LibraryEntry, collection: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let next {
                NavigationLink(value: DetailRoute(itemId: next.entry.id)) {
                    (Text("Next in \(next.collection): ").foregroundStyle(Theme.Palette.textMuted)
                        + Text(next.entry.item.name).foregroundStyle(Theme.Palette.accent))
                        .font(Theme.Font.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            ForEach(copies) { copy in
                NavigationLink(value: DetailRoute(itemId: copy.id)) {
                    (Text("Another copy: ").foregroundStyle(Theme.Palette.textMuted)
                        + Text(fileName(copy)).foregroundStyle(Theme.Palette.accent))
                        .font(Theme.Font.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.shelfInset)
        .task(id: entry.id) {
            copies = await repository.otherCopies(of: entry)
            next = await repository.nextInCollection(after: entry)
        }
    }

    private func fileName(_ copy: LibraryEntry) -> String {
        copy.item.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? copy.item.name
    }
}
