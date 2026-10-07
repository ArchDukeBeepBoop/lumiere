import SwiftUI
import LumiereKit

/// The fixes for collections, duplicate films and file-named episodes.
/// Split out of LibraryHealthCard.swift for the 300-line rule.
extension LibraryHealthCard {

    /// A button for the whole finding, above its samples.
    @ViewBuilder
    func issueActions(_ issue: LibraryHealthIssue) -> some View {
        Group {
            switch issue.kind {
            case "UnnamedEpisodes":
                Button("Use the Titles in Their Filenames") { Task { await useFileTitles() } }
            case "EmptyCollections":
                Button("Fill from the Movie Database") { Task { await fillCollections() } }
            default:
                EmptyView()
            }
        }
        .font(Theme.Font.caption)
        .padding(.leading, Theme.Space.lg)
    }

    /// Buttons on one sample's own row.
    @ViewBuilder
    func sampleActions(_ issue: LibraryHealthIssue, _ sample: LibraryHealthIssue.Sample) -> some View {
        // The files say one show and the library another: Identify, on the show.
        if issue.kind == "MismatchedShows" {
            Button("Identify…") {
                Task { identifying = try? await app.repository?.entry(id: sample.id) }
            }
            Button("Ignore") {
                Task {
                    try? await app.client?.dismissHealth(kind: issue.kind, key: sample.id)
                    await load()
                }
            }
        }
        if issue.kind == "EmptyCollections", let client = app.client {
            SeriesFinder(client: client, collectionId: sample.id, name: sample.name) { note in
                status = note
                Task { await load() }
            }
        }
        if issue.kind == "DuplicateCollections" {
            ForEach(sample.parts ?? []) { other in
                Button("Merge into \(other.name)") { Task { await merge(sample, into: other) } }
            }
            Button("Ignore") {
                Task {
                    try? await app.client?.dismissHealth(kind: issue.kind, key: sample.id)
                    await load()
                }
            }
        }
    }

    /// A duplicated film's copies, each described, each hideable — the worse
    /// one leaves the shelves without anything being deleted.
    @ViewBuilder
    func copyRows(_ issue: LibraryHealthIssue, _ sample: LibraryHealthIssue.Sample) -> some View {
        if issue.kind == "DuplicateFilms" {
            ForEach(sample.parts ?? []) { copy in
                HStack {
                    Text(copy.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Hide This Copy") {
                        Task {
                            try? await app.repository?.hideFromShelves(itemId: copy.id)
                            app.report("That copy is hidden from shelves.") {
                                try? await app.repository?.unhideFromShelves(itemId: copy.id)
                            }
                        }
                    }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .padding(.leading, Theme.Space.xl + Theme.Space.md)
            }
        }
    }

    private func useFileTitles() async {
        guard let client = app.client else { return }
        do {
            let renamed = try await client.useFileTitles()
            app.report("\(renamed) episodes now use the titles in their filenames.") {
                try? await client.undoFileTitles()
                app.startSync(full: true, userInitiated: false)
            }
            app.startSync(full: true, userInitiated: false)
            await load()
        } catch {
            status = "Nothing renamed: \(error.localizedDescription)"
        }
    }

    private func fillCollections() async {
        guard let client = app.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.fillCollections()
            status = "Filled what the movie database knows. What is still empty has no match there."
            await load()
        } catch {
            status = "Nothing added: \(error.localizedDescription)"
        }
    }

    private func merge(_ sample: LibraryHealthIssue.Sample, into other: LibraryHealthIssue.Part) async {
        guard let client = app.client else { return }
        do {
            _ = try await client.mergeCollection(sample.id, into: other.id)
            try? await app.repository?.forgetCollection(id: sample.id)
            status = "\(sample.name) merged into \(other.name)."
            await load()
        } catch {
            status = "Not merged: \(error.localizedDescription)"
        }
    }
}
