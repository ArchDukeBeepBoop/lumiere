import SwiftUI
import LumiereKit

/// Choosing which of TMDB's episode orders a show is named from.
///
/// A show split differently on disk than on TMDB — Justice League's third
/// season, Gintama's count — matches nothing in TMDB's default listing, and
/// its episodes keep only the titles their filenames carry. TMDB keeps other
/// orders for exactly this; picking the one the folders follow names the show
/// properly, synopses and stills included.
struct EpisodeOrderButton: View {
    let repository: LibraryRepository
    let seriesId: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Episode Order…", systemImage: "list.number")
                .font(Theme.Font.cardTitle)
        }
        .buttonStyle(.borderless)
        .labelledHelp("Name this show's episodes from another TMDB order")
        .sheet(isPresented: $isPresented) {
            EpisodeOrderSheet(repository: repository, seriesId: seriesId)
        }
    }
}

private struct EpisodeOrderSheet: View {
    let repository: LibraryRepository
    let seriesId: String

    @Environment(\.dismiss) private var dismiss
    @State private var choice: EpisodeGroupChoice?
    @State private var selected = ""
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Episode Order").font(Theme.Font.sectionHeader)
            Text("Pick the order this show's folders follow. Season 1 on disk becomes "
               + "the order's first part, and so on. Titles and synopses are fetched "
               + "again under it; any you typed yourself are kept.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let choice {
                Picker("Order", selection: $selected) {
                    Text("TMDB's seasons (default)").tag("")
                    ForEach(choice.groups) { group in
                        Text("\(group.name) — \(group.kindName), \(group.groupCount) parts, "
                           + "\(group.episodeCount) episodes"
                           + (group.id == choice.bestFit ? " · matches your folders" : ""))
                            .tag(group.id)
                    }
                }
                .pickerStyle(.radioGroup)
                if choice.groups.isEmpty {
                    Text("TMDB lists no other orders for this show.")
                        .font(Theme.Font.caption)
                }
            } else if message == nil {
                ProgressView().controlSize(.small)
            }
            if let message {
                Text(message).font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Use This Order") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(choice == nil || isSaving || selected == choice?.selected)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .task { await load() }
    }

    private func load() async {
        do {
            let loaded = try await repository.episodeGroups(seriesId: seriesId)
            choice = loaded
            selected = loaded.selected
        } catch {
            message = "The server could not list orders: \(error.localizedDescription)"
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.setEpisodeGroup(seriesId: seriesId, groupId: selected)
            dismiss()
        } catch {
            message = "The server did not take it: \(error.localizedDescription)"
        }
    }
}
