import SwiftUI
import LumiereKit

/// Which libraries feed each Top 10 row.
///
/// Exists because the guess cannot be made from the data. See `TopShelfSelection`.
struct TopShelvesCard: View {
    let libraries: [LibraryRecord]
    let app: AppModel?

    /// Redrawn on change: the toggles read `UserDefaults` directly rather than
    /// through `@AppStorage`, because the key varies per row and per library and
    /// `@AppStorage` needs a fixed one.
    @State private var revision = 0

    private var candidates: [LibraryRecord] {
        TopShelfSelection.candidates(in: libraries)
    }

    var body: some View {
        SettingsCard(
            title: "Top 10 Rows",
            icon: "trophy",
            subtitle: "Which libraries each row ranks"
        ) {
            if candidates.isEmpty {
                SettingsNote("No film or television libraries to rank yet.")
            } else {
                ForEach(LibraryKinds.Kind.allCases, id: \.self) { kind in
                    row(for: kind)
                }
                SettingsNote("Left alone, each row is guessed from your library "
                           + "names — anything named \"anime\" feeds the anime row, "
                           + "the rest split by film and television. Tick anything "
                           + "here and the guess stops applying to that row.")
            }
        }
        .id(revision)
    }

    @ViewBuilder
    private func row(for kind: LibraryKinds.Kind) -> some View {
        let selected = Set(TopShelfSelection.libraryIds(
            for: kind, in: libraries, excluding: app?.privateLibraryIds ?? []
        ))
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(title(for: kind))
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: Theme.Space.md)
                if TopShelfSelection.isChosen(kind) {
                    Button("Reset") { apply { TopShelfSelection.clear(kind) } }
                        .font(Theme.Font.caption)
                }
            }
            // Wrapping, because eleven libraries on one line is a horizontal
            // scroller inside a settings pane.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.xs,
                                   alignment: .leading)],
                alignment: .leading,
                spacing: Theme.Space.xs
            ) {
                ForEach(candidates) { library in
                    chip(library, kind: kind, isOn: selected.contains(library.id))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func chip(_ library: LibraryRecord, kind: LibraryKinds.Kind, isOn: Bool) -> some View {
        Button {
            toggle(library.id, kind: kind, isOn: isOn)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Font.badge)
                Text(library.name).lineLimit(1)
            }
            .font(Theme.Font.caption)
            .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs)
            .background {
                Capsule().fill(
                    isOn ? Theme.Palette.accent.opacity(0.14) : Theme.Palette.surfaceRaised
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func title(for kind: LibraryKinds.Kind) -> String {
        switch kind {
        case .films: return "Top 10 Films"
        case .series: return "Top 10 Series"
        case .anime: return "Top 10 Anime"
        }
    }

    /// Writes the *resolved* set, not a diff against a stored one.
    ///
    /// The first tick on an inferred row has to freeze the guess into a real choice,
    /// otherwise unticking one library would look like it had done nothing — the row
    /// would still be inferred and would still include it.
    private func toggle(_ id: String, kind: LibraryKinds.Kind, isOn: Bool) {
        var ids = Set(TopShelfSelection.libraryIds(
            for: kind, in: libraries, excluding: app?.privateLibraryIds ?? []
        ))
        if isOn { ids.remove(id) } else { ids.insert(id) }
        apply { TopShelfSelection.store(ids, for: kind) }
    }

    private func apply(_ change: () -> Void) {
        change()
        revision &+= 1
        // The shelves are already on screen behind this pane. See `HomeModel.refresh`.
        Task { await app?.homeModel?.refresh() }
    }
}
