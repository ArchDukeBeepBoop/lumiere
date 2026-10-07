import SwiftUI

/// The settings sidebar: the category list, and the search that replaces it.
///
/// Split from SettingsView.swift for the project's 300-line rule. It is a coherent
/// piece on its own — everything here answers "how do I get to the setting I want",
/// which is a different question from what any pane contains.
extension SettingsView {

    // Not private: SettingsView.swift's body composes it.
    var categoryList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.md)

            ShelfSearchField(
                text: $query,
                placeholder: "Search settings",
                matchCount: results.count
            )
            .padding(.horizontal, Theme.Space.xs)
            .padding(.bottom, Theme.Space.md)

            // The list becomes the results while there is a query. Keeping the
            // categories visible under them would leave two lists competing to be
            // clicked, and the categories are exactly what someone searching has
            // given up on navigating.
            if query.isEmpty {
                // Advanced is set apart rather than listed as a fourth peer.
                // It is not a fourth kind of preference; it is the place things
                // go that are not preferences at all.
                ForEach(Category.allCases.filter { $0 != .advanced }) { categoryRow($0) }

                Divider()
                    .padding(.vertical, Theme.Space.xs)
                    .padding(.horizontal, Theme.Space.sm)

                categoryRow(.advanced)
            } else {
                resultList
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(width: 232)
        .background(Theme.Palette.chrome)
    }

    private func categoryRow(_ item: Category) -> some View {
        let isSelected = category == item
        return Button { category = item } label: {
            HStack(spacing: Theme.Space.sm) {
                SettingsIconChip(item.icon, isProminent: isSelected)
                Text(item.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isSelected
                          ? Theme.Palette.accent.opacity(0.14) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.Palette.accent.opacity(0.35) : .clear,
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What the search found, each row naming the pane it will open.
    @ViewBuilder
    private var resultList: some View {
        if results.isEmpty {
            Text("No settings match “\(query)”.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.top, Theme.Space.xs)
        } else {
            ForEach(results) { entry in
                Button {
                    category = entry.category
                    // Names the card, so the pane scrolls to it and rings it —
                    // a result that only switched panes left you at the top of
                    // seven cards, which is the hunt search was meant to end.
                    searchTarget = entry.card
                    // Cleared on the way through: the result has done its job, and
                    // leaving the query up would hide the pane it just opened behind
                    // the list of matches.
                    query = ""
                } label: {
                    HStack(spacing: Theme.Space.sm) {
                        SettingsIconChip(entry.category.icon, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .lineLimit(1)
                            Text(entry.path)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textMuted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, Theme.Space.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var results: [SettingsEntry] { SettingsIndex.matches(query) }
}
