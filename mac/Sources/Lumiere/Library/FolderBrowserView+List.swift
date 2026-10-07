import SwiftUI
import LumiereKit

/// The list layout: one row per item, the way Finder's list view reads.
///
/// Split from the wall for the project's 300-line rule. What a list is *for* here
/// is long names: these libraries are full of files whose titles differ in their
/// last few characters, and under a tile every one of them truncates to the same
/// dozen words. A row gives the name the whole window.
extension FolderBrowserView {

    var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Folders first, as on the wall — the same order, so switching
                    // layout does not also reshuffle what you were looking at.
                    ForEach(visibleFolders + visibleFiles) { entry in
                        listRow(entry).id(entry.id)
                        Divider().padding(.leading, 44)
                    }
                }
                .padding(.vertical, Theme.Space.sm)
            }
            .overlay(alignment: .trailing) {
                if visibleEntries.count > 12 {
                    AlphabetRail(destinations: railDestinations, proxy: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private func listRow(_ entry: LibraryEntry) -> some View {
        let isFolder = entry.item.isFolder
        Button {
            if selection.isActive {
                selection.toggle(entry.id)
            } else if isFolder {
                path.append((id: entry.item.id, name: entry.item.name))
            } else {
                playFromList(entry)
            }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                if selection.isActive {
                    Image(systemName: selection.contains(entry.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(selection.contains(entry.id)
                                         ? Theme.Palette.accent : Theme.Palette.textMuted)
                }

                Image(systemName: isFolder ? "folder.fill" : "film")
                    .font(.system(size: 13))
                    .foregroundStyle(isFolder ? Theme.Palette.accent : Theme.Palette.textMuted)
                    .frame(width: 20)

                Text(displayName(entry))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: Theme.Space.md)

                // The one thing a tile cannot show and a row can: whether it has
                // been watched, stated rather than drawn as a dot in a corner.
                if !isFolder, entry.isPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.accent)
                }
                Text(listDetail(entry))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(MetadataContextMenu(actions: actions(for: entry)))
    }

    /// The trailing column: a runtime for a file, a child count for a folder.
    private func listDetail(_ entry: LibraryEntry) -> String {
        if entry.item.isFolder {
            guard let count = entry.item.childCount, count > 0 else { return "" }
            return "\(count) item\(count == 1 ? "" : "s")"
        }
        guard let seconds = entry.item.runtimeSeconds, seconds > 0 else { return "" }
        let minutes = Int(seconds.rounded()) / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    /// The same merged-file rule the wall plays by; see `FolderBrowserView+Cells`.
    private func playFromList(_ entry: LibraryEntry) {
        if let owner = entry.item.mergedOwnerId {
            onPlay(owner, entry.item.id)
        } else {
            onPlay(entry.item.id, nil)
        }
    }
}
