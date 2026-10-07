import SwiftUI
import LumiereKit

/// The column layout: one pane per level, as Finder's column view.
///
/// The reason to have it is depth. These libraries nest — a series folder holding
/// season folders holding files — and both other layouts show exactly one level at
/// a time, so finding your way back up means reading the breadcrumb and clicking
/// it. Columns keep every level you walked through on screen, and moving sideways
/// costs one click instead of a click and a re-read.
///
/// Panes are read from the same cache the wall uses, keyed by parent id, so
/// stepping back into a folder you have already opened costs nothing.
extension FolderBrowserView {

    var columnContent: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                // One pane per level walked, plus the one you are choosing from.
                ForEach(Array(columnParents.enumerated()), id: \.offset) { depth, parent in
                    pane(parentId: parent, depth: depth)
                    Divider()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task(id: columnParents.joined(separator: "/")) { await loadColumns() }
    }

    /// The parent id of each pane, left to right: the library, then each folder
    /// stepped into.
    var columnParents: [String] {
        [libraryId] + path.map(\.id)
    }

    @ViewBuilder
    private func pane(parentId: String, depth: Int) -> some View {
        let rows = columnCache[parentId]
        VStack(spacing: 0) {
            if let rows {
                if rows.isEmpty {
                    Text("Empty")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { entry in
                                columnRow(entry, depth: depth)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 260)
    }

    @ViewBuilder
    private func columnRow(_ entry: LibraryEntry, depth: Int) -> some View {
        // The row that was chosen at this depth, which is the next pane's parent.
        let isChosen = depth < path.count && path[depth].id == entry.item.id
        Button {
            if entry.item.isFolder {
                // Truncate before appending: clicking in a pane you have already
                // walked past replaces everything to its right, rather than
                // appending a level under a folder you are no longer in.
                path = Array(path.prefix(depth))
                path.append((id: entry.item.id, name: entry.item.name))
            } else {
                playFromColumn(entry)
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: entry.item.isFolder ? "folder.fill" : "film")
                    .font(.system(size: 11))
                    .foregroundStyle(isChosen
                                     ? Theme.Palette.textPrimary
                                     : (entry.item.isFolder
                                        ? Theme.Palette.accent : Theme.Palette.textMuted))
                    .frame(width: 16)

                Text(displayName(entry))
                    .font(Theme.Font.caption)
                    .foregroundStyle(isChosen
                                     ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                // The chevron a column view is read by: it says this row goes
                // somewhere, before you click it.
                if entry.item.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 5)
            .background(
                isChosen ? Theme.Palette.surfaceRaised : .clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.badge)
            )
            .padding(.horizontal, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(MetadataContextMenu(actions: actions(for: entry)))
    }

    /// Fills any pane that has not been read yet.
    ///
    /// Only the missing ones: walking back up a path must not re-fetch every level
    /// above it, and the cache is what makes moving between siblings feel like
    /// moving rather than loading.
    func loadColumns() async {
        for parent in columnParents where columnCache[parent] == nil {
            let rows = (try? await (parent == libraryId
                ? repository.libraryRootChildren(libraryId: libraryId)
                : repository.folderChildren(parentId: parent))) ?? []
            columnCache[parent] = rows
        }
    }

    private func playFromColumn(_ entry: LibraryEntry) {
        if let owner = entry.item.mergedOwnerId {
            onPlay(owner, entry.item.id)
        } else {
            onPlay(entry.item.id, nil)
        }
    }
}
