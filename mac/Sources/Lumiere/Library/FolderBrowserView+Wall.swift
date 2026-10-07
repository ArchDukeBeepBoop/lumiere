import SwiftUI
import LumiereKit

/// The wall itself: what a folder's contents look like laid out.
///
/// Split from FolderBrowserView.swift for the project's 300-line limit. Not private,
/// for the usual reason — Swift scopes `private` to the file and the body that draws
/// this lives next door.
extension FolderBrowserView {

    /// Which layout is showing. The three cases differ only below the empty and
    /// loading states, which every layout shares.
    @ViewBuilder
    var content: some View {
        switch viewMode {
        case .icon:   iconContent
        case .list:   emptyOr(listContent)
        case .column: columnContent
        }
    }

    /// The states that come before a layout: still reading, or nothing to lay out.
    ///
    /// Columns are exempt — a column view draws its own per-pane spinner, and a
    /// full-screen one over it would hide the panes that are already filled.
    @ViewBuilder
    func emptyOr<Layout: View>(_ layout: Layout) -> some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            emptyState
        } else {
            layout
        }
    }

    var emptyState: some View {
        EmptyStateView(reason: .empty(
            icon: neverSynced ? "arrow.triangle.2.circlepath" : "folder",
            title: neverSynced ? "Not synced yet" : "Empty folder",
            detail: neverSynced
                ? "This library's contents have not finished syncing. Folders appear "
                + "as they arrive."
                : "This folder has no videos in it — either nothing was put here, or "
                + "what is here is not a format Lumiere plays."
        ))
    }

    @ViewBuilder
    var iconContent: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            EmptyStateView(reason: .empty(
                icon: neverSynced ? "arrow.triangle.2.circlepath" : "folder",
                title: neverSynced ? "Not synced yet" : "Empty folder",
                detail: neverSynced
                    ? "This library's contents have not finished syncing. Folders appear "
                    + "as they arrive."
                    : "This folder has no videos in it — either nothing was put here, or "
                + "what is here is not a format Lumiere plays."
            ))
        } else {
            // Measured rather than adaptive. The grid below counts its own columns,
            // which means it has to be told how much room it has; a `GeometryReader`
            // here is the only honest source for that, and it costs nothing because
            // it wraps the scroll view rather than sitting inside its content.
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        // Folders above files. Splitting them is what lets each
                        // section pick a column width its own tiles fill exactly —
                        // a folder tile is a square off the size slider, a video is
                        // a 384pt Continue Watching card, and one column width
                        // cannot hold both without stranding the smaller.
                        VStack(alignment: .leading, spacing: Theme.Space.xl) {
                            if !visibleFolders.isEmpty {
                                grid(
                                    visibleFolders, width: cellWidth,
                                    available: available(in: geometry)
                                )
                            }
                            if !visibleFiles.isEmpty {
                                grid(
                                    visibleFiles, width: fileWidth,
                                    available: available(in: geometry)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.lg)
                    }
                    // Overlaid rather than beside, so the grid keeps its full width
                    // and the columns do not reflow when the rail appears.
                    .overlay(alignment: .trailing) {
                        if visibleEntries.count > 12 {
                            AlphabetRail(destinations: railDestinations, proxy: proxy)
                        }
                    }
                }
            }
        }
    }

    /// The room a row of tiles actually has: the window, less the wall's own padding
    /// on both sides. The A–Z rail is not subtracted — it is an overlay, drawn over
    /// the last column's own margin rather than taking width from the grid.
    func available(in geometry: GeometryProxy) -> CGFloat {
        geometry.size.width - Theme.Space.lg * 2
    }

}
