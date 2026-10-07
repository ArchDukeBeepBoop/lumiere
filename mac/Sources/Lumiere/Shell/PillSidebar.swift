import SwiftUI
import LumiereKit

/// Navigation as Apple TV draws it: a floating pill down the left edge.
///
/// It replaces both the old full-height sidebar and the bar across the top.
/// Collapsed it is a column of icons; pointing at it opens it over the page
/// with the names beside them, and the pin keeps it open, the page moving over
/// to make room. The place you are is a filled capsule, as on Apple TV — not a
/// tinted row, which on glass read as a smudge.
struct PillSidebar: View {
    @Bindable var app: AppModel
    let route: Route
    /// Kept open: the old "show the sidebar" choice, remembered the same way.
    @Binding var isPinned: Bool
    let onGenre: (String) -> Void
    let onSync: () -> Void

    @State private var isHovering = false
    /// The row the keyboard is on. The pill opens while it is in there.
    @FocusState private var focusedRow: String?
    /// Whether that focus came from a key. Opening a page leaves the clicked
    /// poster gone, and macOS hands focus to the first thing that will take
    /// it — this pill's top row — which opened the pill on a series page
    /// nobody had pointed at. Only focus a key brought here opens it.
    @State private var keyFocus = false
    @State private var genres: [String] = []
    @State private var pick: LibraryEntry?

    static let collapsedWidth: CGFloat = 60
    static let expandedWidth: CGFloat = 232
    static let margin: CGFloat = 12

    private var isOpen: Bool { isPinned || isHovering || (keyFocus && focusedRow != nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    row("Home", icon: "house", to: .home)
                    row("Search", icon: "magnifyingglass", to: .search)
                    row("Favourites", icon: "star", to: .favourites)
                    action("Shuffle", icon: "shuffle") { Task { await draw() } }
                        .popover(item: $pick, arrowEdge: .trailing) { entry in
                            ShufflePick(entry: entry,
                                        onPlay: { pick = nil; app.nowPlayingItemId = entry.id },
                                        onAnother: { Task { await draw() } },
                                        onOpen: {
                                            pick = nil
                                            NotificationCenter.default.post(name: .openDetail, object: entry.id)
                                        })
                        }
                    genreMenu
                    divider
                    ForEach(app.visibleLibraries) { library in
                        row(library.name, icon: LibraryGlyph.name(for: library.collectionType),
                            to: .library(id: library.id, name: library.name))
                    }
                    if app.hasPrivateLibraries {
                        divider
                        action(app.isShowingPrivateLibraries ? "Leave Private Room" : "Private Room",
                               icon: app.isShowingPrivateLibraries ? "eye" : "eye.slash",
                               isLit: app.isShowingPrivateLibraries) {
                            Task {
                                if app.isShowingPrivateLibraries { await app.leaveRoom() } else { await app.enterRoom() }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            action(app.syncProgress.map { "Syncing \($0.libraryName)" } ?? "Library Sync",
                   icon: app.syncProgress == nil ? "arrow.clockwise" : "arrow.triangle.2.circlepath",
                   action: onSync)
            row("Settings", icon: "gearshape", to: .settings,
                dot: LibraryHealthWatch.shared.hasNews)
        }
        .padding(8)
        .frame(width: isOpen ? Self.expandedWidth : Self.collapsedWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Theme.Palette.chrome.opacity(0.55))
                }
                .shadow(color: .black.opacity(isOpen && !isPinned ? 0.35 : 0.18), radius: 18, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        // ← from the page lands here; → goes back out. See `ShellView`.
        .focusSection()
        .onChange(of: focusedRow) {
            // Tab and the arrows move focus; Return opening a title does not.
            let event = NSApp.currentEvent
            keyFocus = focusedRow != nil && event?.type == .keyDown
                && [48, 123, 124, 125, 126].contains(Int(event?.keyCode ?? 0))
        }
        .onHover { hovering in
            withAnimation(Theme.Motion.transition) { isHovering = hovering }
        }
        .animation(Theme.Motion.transition, value: isOpen)
        .task(id: app.libraries.map(\.id)) { await loadGenres() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .frame(width: 44, height: 40)
            if isOpen {
                Text("Lumiere")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
                Button { isPinned.toggle() } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labelledHelp(isPinned ? "Let it fold away" : "Keep it open")
            }
        }
        .padding(.bottom, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.border)
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func row(_ title: String, icon: String, to destination: Route, dot: Bool = false) -> some View {
        let current = route == destination
        return Button { choose { app.pendingRoute = destination } } label: {
            label(title, icon: icon, isCurrent: current, isLit: false, dot: dot)
        }
        .buttonStyle(.plain)
        .modifier(PillKey(id: title, focused: $focusedRow, ringed: keyFocus) { choose { app.pendingRoute = destination } })
        .labelledHelp(isOpen ? "" : title)
        .accessibilityLabel(title)
    }

    private func action(_ title: String, icon: String, isLit: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button { choose(action) } label: {
            label(title, icon: icon, isCurrent: false, isLit: isLit, dot: false)
        }
        .buttonStyle(.plain)
        .modifier(PillKey(id: title, focused: $focusedRow, ringed: keyFocus) { choose(action) })
        .labelledHelp(isOpen ? "" : title)
        .accessibilityLabel(title)
    }

    /// Does what the row is for, then folds the pill. A click also gives the
    /// row keyboard focus, and the pill stays open while a row has focus — so
    /// without letting go of it here, it stayed open after the pointer left.
    private func choose(_ action: () -> Void) {
        action()
        focusedRow = nil
        keyFocus = false
        withAnimation(Theme.Motion.transition) { isHovering = false }
    }

    private var genreMenu: some View {
        Menu {
            if genres.isEmpty { Text("No genres yet") }
            ForEach(genres, id: \.self) { genre in Button(genre) { onGenre(genre) } }
        } label: {
            label("Genres", icon: "theatermasks", isCurrent: false, isLit: false, dot: false)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Genres")
    }

    /// One row: the icon always, the name when open; the current one a filled
    /// capsule, as on Apple TV.
    private func label(_ title: String, icon: String, isCurrent: Bool, isLit: Bool, dot: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                .frame(width: 44, height: 36)
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(Theme.Palette.accent).frame(width: 7, height: 7).offset(x: -8, y: 7)
                    }
                }
            if isOpen {
                Text(title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(isCurrent ? Theme.Palette.canvas
                         : isLit ? Theme.Palette.accent : Theme.Palette.textPrimary)
        .background {
            if isCurrent {
                Capsule().fill(Theme.Palette.textPrimary)
            }
        }
        .contentShape(Capsule())
    }

    private func draw() async {
        guard let entry = try? await app.repository?.randomPlayable() else {
            pick = nil
            app.report("Nothing left to shuffle — everything is watched.")
            return
        }
        if Preference.shufflePlaysAtOnce.value { app.nowPlayingItemId = entry.id } else { pick = entry }
    }

    private func loadGenres() async {
        guard genres.isEmpty, let repository = app.repository else { return }
        genres = ((try? await repository.genreTallies(types: LibraryRepository.topLevelTypes)) ?? []).map(\.name)
    }
}

/// A pill row the keyboard can reach: focusable, ringed while it has focus,
/// opened with Return or Space.
private struct PillKey: ViewModifier {
    let id: String
    var focused: FocusState<String?>.Binding
    /// Only when the keyboard brought focus here; see `keyFocus`.
    let ringed: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focused, equals: id)
            .overlay {
                if ringed, focused.wrappedValue == id {
                    Capsule().strokeBorder(Theme.Palette.accent, lineWidth: 2).allowsHitTesting(false)
                }
            }
            .onKeyPress(.return) { action(); return .handled }
            .onKeyPress(.space) { action(); return .handled }
    }
}
