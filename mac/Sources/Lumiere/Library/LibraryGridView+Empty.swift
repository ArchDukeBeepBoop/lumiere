import SwiftUI
import LumiereKit

/// The grid's empty states and its sort labels.
///
/// Split from LibraryGridView.swift to keep it under the project's 300-line limit;
/// the related-collections scan was what pushed it over. Nothing private here —
/// Swift's `private` is file-scoped, so the halves have to see each other.
extension LibraryGridView {

    func label(for sort: LibraryRepository.Sort) -> String {
        switch sort {
        case .title: return "Title"
        case .dateAdded: return "Date added"
        case .releaseDate: return "Release date"
        case .rating: return "Rating"
        case .runtime: return "Runtime"
        case .watched: return "Most watched"
        // Never reachable from this menu — see `Sort.userSelectable` — but named
        // rather than defaulted, so adding a sort later is a compile error here
        // instead of a row that silently reads "Title".
        case .latestContent: return "Latest"
        }
    }

    @ViewBuilder
    var emptyState: some View {
        if !isLoading && entries.isEmpty {
            VStack(spacing: Theme.Space.sm) {
                Image(systemName: unwatchedOnly ? "checkmark.circle" : "film.stack")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Palette.textDisabled)
                Text(emptyTitle)
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if unwatchedOnly || genre != nil || studio != nil
                    || !searchTerm.isEmpty {
                    Button("Clear filters") {
                        unwatchedOnly = false
                        genre = nil
                        studio = nil
                        // Was omitted, so the one filter you can empty the grid
                        // with by accident was the one Clear would not clear.
                        shelfFilter = ""
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.accent)
                }
            }
        }
    }

    var searchTerm: String { shelfFilter.trimmingCharacters(in: .whitespaces) }

    /// Says which filter emptied the view, rather than implying the library is.
    ///
    /// The search term comes first and is checked everywhere, because it is the
    /// filter most easily emptied by accident and the only one with no visible
    /// chip to explain itself. It was not consulted at all: typing three letters
    /// that matched nothing produced "This library is empty", which on a library
    /// of this size reads as data loss rather than a miss.
    ///
    /// Every clause below names *all* the active filters rather than the first
    /// one found, for the same reason — "Nothing from Bones" while
    /// unwatched-only is on blames the studio for the wrong thing.
    var emptyTitle: String {
        let term = searchTerm
        var scope: [String] = []
        if let studio { scope.append("from \(studio)") }
        if let genre { scope.append("in \(genre)") }

        if !term.isEmpty {
            let where_ = scope.isEmpty ? "" : " " + scope.joined(separator: " ")
            return unwatchedOnly
                ? "Nothing unwatched matching \u{201C}\(term)\u{201D}\(where_)"
                : "No matches for \u{201C}\(term)\u{201D}\(where_)"
        }
        if !scope.isEmpty {
            let where_ = scope.joined(separator: " ")
            return unwatchedOnly
                ? "Nothing unwatched \(where_)"
                : "Nothing \(where_)"
        }
        if unwatchedOnly { return "You've watched everything here" }
        return "This library is empty"
    }
}

/// The filter and the jump rail.
///
/// Both act on what is already loaded rather than asking the server again. The grid
/// pages as you scroll, so a server-side filter would fight the paging — and the
/// rail can only point at rows that exist, which is why it appears on the title
/// sort alone: jumping to "S" in date-added order would land somewhere arbitrary.
extension LibraryGridView {
    /// The query already applied the filter, so this is simply what was loaded.
    ///
    /// It used to filter the loaded rows here — sixty out of twenty-four thousand
    /// — which is why typing part of a title so often found nothing: the match was
    /// real, it was just three hundred pages further down.
    var visibleEntries: [LibraryEntry] { entries }

    /// Hidden in any sort but title, where a letter would land somewhere arbitrary,
    /// and on a library short enough to scroll.
    var showsRail: Bool {
        sort == .title && (anchors.count > 3 || visibleEntries.count > 30)
    }

    /// Library-wide while unfiltered; local once a filter narrows things.
    ///
    /// The filter is applied to loaded rows only, so the anchors — which describe
    /// the whole library — would point at titles the filter has removed. Falling
    /// back to what is on screen is the honest answer there.
    var railDestinations: [String: String] {
        guard shelfFilter.trimmingCharacters(in: .whitespaces).isEmpty, !anchors.isEmpty else {
            return AlphabetIndex.firstIds(
                in: visibleEntries,
                id: { $0.id },
                sortKey: { $0.item.sortName },
                name: { $0.item.name }
            )
        }
        return Dictionary(uniqueKeysWithValues: anchors.map { ($0.letter, $0.id) })
    }

    /// Loads pages until the row a letter points at actually exists.
    ///
    /// The fix for the jump that only worked after scrolling to the bottom: the
    /// grid holds a window, `scrollTo` can only reach rows in it, and every letter
    /// past the first page pointed at a row that had never been rendered. Scrolling
    /// to Z loaded everything on the way, which is why it looked as though the rail
    /// woke up once you got there.
    func loadThrough(letter: String) async {
        guard let anchor = anchors.first(where: { $0.letter == letter }) else { return }
        // One row past the anchor, so the target is inside the window rather than
        // exactly on its edge.
        while entries.count <= anchor.offset, entries.count < total {
            let before = entries.count
            await loadPage()
            // A page that returns nothing would otherwise spin here forever.
            if entries.count == before { break }
        }
    }
}

/// The tile-size slider.
///
/// Moved here purely for the 300-line limit; the filter field and jump rail pushed
/// the main file over. Not private, since the toolbar that draws it lives next door.
extension LibraryGridView {
    /// Smaller tiles fit more per row; larger ones read better from a couch. Range
    /// runs 100–220pt, wide enough to roughly double or halve how many columns fit
    /// without either extreme going illegible or absurdly oversized.
    var tileSizeControl: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textMuted)
            // Committed on release, not continuously. The width feeds the image
            // request key, so dragging 100→220 re-requested and re-decoded every
            // visible poster at each of the twelve steps on the way.
            Slider(
                // Up to 260 now, not 220. The review asked for a genuinely
                // large mode for *browsing* rather than finding, and 220 is
                // still a thumbnail.
                value: $draftTileWidth, in: 100...260, step: 10,
                onEditingChanged: { editing in
                    if !editing { tileWidth = draftTileWidth }
                }
            )
            .frame(width: 90)
            .onAppear { draftTileWidth = tileWidth }
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .labelledHelp("Tile size")
    }
}
