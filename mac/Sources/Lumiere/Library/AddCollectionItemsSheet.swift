import SwiftUI
import LumiereKit

/// Search the whole library and add matches to whichever collection is already
/// open. Local search only — the same instant, no-round-trip pass `SearchView`
/// does — because what you are looking for to add almost certainly already
/// synced; the point here is picking members quickly, not discovering new titles.
struct AddCollectionItemsSheet: View {
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL
    /// Already members — filtered out so they cannot be "added" twice.
    let excludedIds: Set<String>
    let onAdd: ([String]) async -> Void

    @State private var query = ""
    @State private var results: [LibraryEntry] = []
    @State private var selected: Set<String> = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: Theme.Space.md, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            content
        }
        .frame(width: 640, height: 560)
        .background(Theme.Palette.canvas)
    }

    private var header: some View {
        HStack {
            Text("Add Items")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            if !selected.isEmpty {
                Text("\(selected.count) selected")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add") {
                Task {
                    await onAdd(Array(selected))
                    dismiss()
                }
            }
            .disabled(selected.isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Space.lg)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textMuted)
            TextField("Search your library", text: $query)
                .textFieldStyle(.plain)
                .onChange(of: query) { search() }
            if isSearching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
    }

    @ViewBuilder
    private var content: some View {
        let addable = results.filter { !excludedIds.contains($0.id) }
        if query.isEmpty {
            Text("Search for movies or series to add — anime, movies and TV all mix freely.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .multilineTextAlignment(.center)
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if addable.isEmpty {
            Text(isSearching ? "Searching…" : "No matches for \"\(query)\".")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Space.lg) {
                    ForEach(addable) { entry in
                        cell(entry)
                    }
                }
                .padding(Theme.Space.lg)
            }
        }
    }

    private func cell(_ entry: LibraryEntry) -> some View {
        Button {
            if selected.contains(entry.id) {
                selected.remove(entry.id)
            } else {
                selected.insert(entry.id)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                PosterCard(entry: entry, serverURL: serverURL, pipeline: pipeline, width: 120)
                if selected.contains(entry.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.Palette.canvas, Theme.Palette.accent)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Debounced and cancellable, same as `SearchView` — typing fast must not
    /// let a stale query land after a newer one.
    private func search() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let local = (try? await repository.entries(
                types: [.movie, .series], sort: .title, limit: 120, searchTerm: term
            )) ?? []
            guard !Task.isCancelled else { return }
            results = local
        }
    }
}
