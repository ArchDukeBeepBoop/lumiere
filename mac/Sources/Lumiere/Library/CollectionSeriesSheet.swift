import SwiftUI
import LumiereKit

/// Finding a collection in the movie database: the film series, their
/// posters, and how many of their films are here.
///
/// Two uses. Identify — this collection *is* that series: it takes its name,
/// synopsis, poster and backdrop, and its films here join it. Discover — a
/// new collection of the series' films, made in the room you are in: inside
/// the private room only private films are counted and gathered, outside
/// only the rest.
struct CollectionSeriesSheet: View {
    enum Mode { case identify(collectionId: String), discover }

    let mode: Mode
    let client: JellyfinClient
    let initialQuery: String
    let privateLibraryIds: Set<String>
    let inRoom: Bool
    let onDone: (_ changed: Bool) -> Void

    @State private var query = ""
    @State private var results: [DiscoveredCollection] = []
    @State private var isSearching = false
    @State private var working: String?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text(isIdentify ? "Identify Collection" : "Discover Collections")
                .font(Theme.Font.title)
            HStack {
                TextField("Search the movie database's collections", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button("Search") { Task { await search() } }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if isSearching { ProgressView().controlSize(.small) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(results) { row($0) }
                }
            }
            if let message {
                Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
            }
            HStack {
                Spacer()
                Button("Done") { onDone(false) }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 620, height: 560)
        .task {
            query = initialQuery
            if !query.isEmpty { await search() }
        }
    }

    private var isIdentify: Bool { if case .identify = mode { true } else { false } }

    /// The films here that belong to the room being looked from.
    private func roomHeld(_ c: DiscoveredCollection) -> [DiscoveredCollection.Held] {
        c.held.filter { privateLibraryIds.contains($0.library) == inRoom }
    }

    private func row(_ c: DiscoveredCollection) -> some View {
        let held = roomHeld(c)
        return HStack(alignment: .top, spacing: Theme.Space.md) {
            AsyncImage(url: c.poster.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.Palette.surface
            }
            .frame(width: 64, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(c.name).font(Theme.Font.cardTitleLarge)
                Text(heldLine(held.count, of: c.parts))
                    .font(Theme.Font.caption)
                    .foregroundStyle(held.isEmpty ? Theme.Palette.textMuted : Theme.Palette.accent)
                if let overview = c.overview, !overview.isEmpty {
                    Text(overview).font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Button(isIdentify ? "Choose" : "Create") { Task { await act(c, held: held) } }
                .disabled(working != nil || (!isIdentify && held.count < 1))
        }
        .padding(Theme.Space.sm)
        .background(Theme.Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func heldLine(_ held: Int, of parts: Int?) -> String {
        let total = parts.map { " of \($0)" } ?? ""
        return held == 0 ? "None of its films here" : "\(held)\(total) films here"
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await client.discoverCollections(query)
            message = results.isEmpty ? "No collections by that name." : nil
        } catch {
            message = "The search did not complete: \(error.localizedDescription)"
        }
    }

    private func act(_ c: DiscoveredCollection, held: [DiscoveredCollection.Held]) async {
        working = c.tmdbId
        defer { working = nil }
        do {
            switch mode {
            case .identify(let id):
                try await client.identifyCollection(id, as: c.tmdbId)
            case .discover:
                _ = try await client.createCollection(fromSeries: c.tmdbId, itemIds: held.map(\.id), inRoom: inRoom)
            }
            onDone(true)
        } catch {
            message = "That did not work: \(error.localizedDescription)"
        }
    }
}
