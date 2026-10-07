import SwiftUI
import LumiereKit

/// "Find Its Series…" on an empty collection in Library Health: search the
/// movie database by any name, pick the series, and the server fills the
/// collection with the films of it that are here. For the collections whose
/// own name matched nothing exactly.
struct SeriesFinder: View {
    let client: JellyfinClient
    let collectionId: String
    let name: String
    let onDone: (String) -> Void

    @State private var isOpen = false
    @State private var query = ""
    @State private var results: [SeriesMatch] = []
    @State private var message: String?

    var body: some View {
        Button("Find Its Series…") {
            query = name.replacingOccurrences(of: " Collection", with: "")
            isOpen = true
            Task { await search() }
        }
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                TextField("Series name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                if let message {
                    Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                }
                ForEach(results) { match in
                    Button(match.name) { Task { await choose(match) } }
                        .buttonStyle(.link)
                }
            }
            .padding(Theme.Space.md)
            .frame(width: 320)
        }
    }

    private func search() async {
        message = "Searching…"
        do {
            results = try await client.searchSeries(name: query)
            message = results.isEmpty ? "Nothing by that name. Try another." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func choose(_ match: SeriesMatch) async {
        message = "Filling…"
        do {
            try await client.setSeries(collectionId: collectionId, tmdbId: match.id)
            isOpen = false
            onDone("\(name) is now \(match.name), filled with the films of it you have.")
        } catch {
            message = error.localizedDescription
        }
    }
}
