import SwiftUI
import LumiereKit

/// The library row, on every home layout.
///
/// This is the row that replaces the sidebar. The sidebar listed eleven libraries
/// as eleven words in a column you had to read; here they are eleven pieces of
/// artwork side by side, at the top of the screen, and clicking one opens exactly
/// what the sidebar row opened — the same `LibraryRecord` handed to the same
/// callback, so the grid/folder/server-browser decision in the shell is made once
/// and both routes inherit it.
///
/// Built as an ordinary `Shelf`, like `GenreShelf`, so it inherits the title card,
/// the insets and the hover room every other row on the screen has. The only
/// thing different about it is what the tiles are.
struct LibraryShelf: View {
    let libraries: [LibraryCardItem]
    let serverURL: URL
    let pipeline: ImagePipeline
    /// The same closure the "See All" on a Latest shelf uses, which is the same
    /// one the sidebar's selection drives.
    let onOpen: (LibraryRecord) -> Void

    var body: some View {
        if !libraries.isEmpty {
            Shelf(
                title: "Your Libraries", subtitle: subtitle,
                itemCount: libraries.count, itemWidth: Theme.Art.libraryCardWidth
            ) {
                ForEach(libraries) { item in
                    // A Button rather than a NavigationLink, unlike the genre row.
                    // A library is a *section* — it replaces what the detail column
                    // is showing and resets the back stack — where a genre pushes
                    // on top of Home. Pushing a library instead would leave the
                    // shell's route on Home while a whole library sat on the stack,
                    // which is the state the sidebar selection is meant to reflect.
                    Button { onOpen(item.library) } label: {
                        LibraryCard(item: item, serverURL: serverURL, pipeline: pipeline)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Counted rather than named, which is the opposite of the genre row's choice.
    /// "10 genres" is a fact about a row that shows ten of sixty; this row shows
    /// every library there is, so the number is the whole inventory and worth
    /// saying.
    private var subtitle: String {
        libraries.count == 1 ? "1 library" : "\(libraries.count) libraries"
    }
}

/// Favourites, Search and Settings, as a strip above the library row.
///
/// These three have no artwork to be a card of — Favourites is a list that may be
/// empty, Search is a field, Settings is a form — so making them poster tiles
/// would be a lie about what is behind them and would push the actual libraries
/// off the first screen. They stay small, quiet and chrome-coloured, sitting
/// above the artwork rather than in it, which is the same relationship the
/// sidebar gave them.
///
/// Routed through `AppModel.pendingRoute`, which is the mechanism the menu bar
/// already uses to switch section from outside the shell. No new plumbing, and
/// one path into a route change rather than two.
struct HomeQuickLinks: View {
    var app: AppModel?

    var body: some View {
        if let app {
            HStack(spacing: Theme.Space.sm) {
                link("Favourites", icon: "star", route: .favourites, app: app)
                link("Search", icon: "magnifyingglass", route: .search, app: app)
                link("Settings", icon: "gearshape", route: .settings, app: app)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.shelfInset)
        }
    }

    private func link(
        _ title: String, icon: String, route: Route, app: AppModel
    ) -> some View {
        QuickLinkPill(title: title, icon: icon) { app.pendingRoute = route }
    }
}

/// One quick link. Its own type only because it needs hover state of its own, and
/// a `@State` per pill cannot live on the parent that draws three of them.
///
/// Shaped like the "See All" pill in a shelf header — bordered capsule, fill only
/// while hovered — so the two read as the same kind of control. Twelve
/// permanently filled pills down a home screen compete with the artwork they
/// point at; three unfilled ones do not.
private struct QuickLinkPill: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: icon).font(Theme.Font.badge)
                Text(title)
            }
            .font(Theme.Font.cardTitle)
            .foregroundStyle(
                isHovering ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
            )
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(
                isHovering ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
    }
}
