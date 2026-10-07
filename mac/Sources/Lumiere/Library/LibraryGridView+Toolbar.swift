import SwiftUI
import LumiereKit

/// The grid's toolbar: search, sort, and one button holding everything else.
///
/// It used to carry seven controls of equal weight in one row — filter, tile
/// size, unwatched, genre, studio, sort, direction — which is a database front
/// end rather than a way to look at a collection. Nothing in it said what was
/// currently being shown, either: a genre picker reading "Action" is a control's
/// state, not a sentence about the grid beneath it.
///
/// So: two controls in view, the rest behind one button that carries a count,
/// and the active filter written out underneath in words you can dismantle.
extension LibraryGridView {

    // MARK: - Toolbar

    var toolbar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.Font.shelfHeader)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(total > 0 ? "\(total) items" : " ")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }

                Spacer()

                ShelfSearchField(
                    text: $shelfFilter,
                    placeholder: "Search \(title)",
                    matchCount: total
                )
                // Re-queries rather than narrowing what is on screen. Debounced,
                // because a keystroke is not a search — typing "monogatari"
                // would otherwise be eleven full queries against 24,000 rows.
                .onChange(of: shelfFilter) {
                    filterTask?.cancel()
                    filterTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await reload()
                    }
                }

                sortControl
                filterButton
                actionsMenu
            }

            LibraryTabBar(available: availableTabs, selection: $tab)
            activeFilterLine
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.vertical, Theme.Space.md)
        .liquidGlass(Rectangle())
    }

    /// Sort stays in view. It is the one control that changes what the grid
    /// *is* rather than what it contains, and it is used on every visit.
    private var sortControl: some View {
        HStack(spacing: 2) {
            Picker("Sort", selection: $sort) {
                ForEach(LibraryRepository.Sort.userSelectable, id: \.self) { option in
                    Text(label(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 132)
            .onChange(of: sort) {
                descending = nil
                Task { await reload() }
            }

            Button {
                descending = !(descending ?? sort.defaultDescending)
                Task { await reload() }
            } label: {
                Image(systemName: (descending ?? sort.defaultDescending)
                      ? "arrow.down" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.textSecondary)
            .labelledHelp("Reverse the sort order")
        }
    }

    /// Everything that narrows the grid, behind one control that says how much
    /// is currently doing so.
    private var filterButton: some View {
        Menu {
            Toggle("Unwatched only", isOn: $unwatchedOnly)
                .onChange(of: unwatchedOnly) { Task { await reload() } }

            if !genres.isEmpty {
                Picker("Genre", selection: $genre) {
                    Text("All genres").tag(String?.none)
                    ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .onChange(of: genre) { Task { await reload() } }
            }

            if !studios.isEmpty {
                Picker("Studio", selection: $studio) {
                    Text("All studios").tag(String?.none)
                    ForEach(studios, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .onChange(of: studio) { Task { await reload() } }
            }

            Divider()
            tileSizeControl

            if activeFilters > 0 {
                Divider()
                Button("Clear filters") { clearFilters() }
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .semibold))
                Text(activeFilters > 0 ? "Filter · \(activeFilters)" : "Filter")
                    .font(Theme.Font.caption)
            }
            .foregroundStyle(activeFilters > 0
                             ? Theme.Palette.accent : Theme.Palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The three commands that act on the library rather than describing it.
    /// Icons in a row read as equal in weight to the controls beside them; they
    /// are not, and they are used once a month.
    private var actionsMenu: some View {
        Menu {
            Button(selection.isActive ? "Stop Selecting" : "Select Several…") {
                selection.isActive ? selection.end() : selection.begin()
            }
            Button("Find Collections…") { isProposingCollections = true }
            Button("Discover Collections…") { isDiscoveringCollections = true }
            Button("Repair Episode Numbering…") { isScanningMergedSeries = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(selection.isActive
                                 ? Theme.Palette.accent : Theme.Palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// What you are actually looking at, in words.
    ///
    /// The one thing seven pickers could not do. Each clause is a button that
    /// removes itself, so the sentence is also the way out of it.
    @ViewBuilder
    private var activeFilterLine: some View {
        if activeFilters > 0 {
            HStack(spacing: Theme.Space.xs) {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)

                if let genre {
                    filterClause(genre) { self.genre = nil; Task { await reload() } }
                }
                if let studio {
                    filterClause(studio) { self.studio = nil; Task { await reload() } }
                }
                if unwatchedOnly {
                    filterClause("unwatched") {
                        unwatchedOnly = false
                        Task { await reload() }
                    }
                }

                Text("— \(total) title\(total == 1 ? "" : "s")")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .monospacedDigit()
            }
        }
    }

    private func filterClause(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 3) {
                Text("·").foregroundStyle(Theme.Palette.textMuted)
                Text(text)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.accent)
        }
        .buttonStyle(.plain)
        .labelledHelp("Remove this filter")
    }

    /// How many things are narrowing the grid right now.
    ///
    /// The search term counts. It narrows the grid harder than any of the
    /// others and it was not counted, so a typed term left the filter button
    /// showing no badge while the grid showed nothing.
    var activeFilters: Int {
        [genre != nil, studio != nil, unwatchedOnly, !searchTerm.isEmpty]
            .filter { $0 }.count
    }

    func clearFilters() {
        genre = nil
        studio = nil
        unwatchedOnly = false
        shelfFilter = ""
        Task { await reload() }
    }
}
