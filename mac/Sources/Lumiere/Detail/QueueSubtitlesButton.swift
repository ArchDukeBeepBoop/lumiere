import SwiftUI
import LumiereKit

/// Queues subtitles for the season on screen. See the server's subtitle queue:
/// the provider allows a handful of downloads a day, so a season is fetched
/// over days, synced to the audio as each one arrives.
struct QueueSubtitlesButton: View {
    let repository: LibraryRepository
    let seriesId: String
    let seasonId: String?
    let seasonName: String

    @State private var isAsking = false
    @State private var result: String?

    private var language: String {
        let first = Preference.subtitleSearchLanguage.value
            .split(separator: ",").first.map(String.init) ?? "en"
        return first.trimmingCharacters(in: .whitespaces).isEmpty ? "en" : first.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Button {
            isAsking = true
        } label: {
            Label("Queue Subtitles…", systemImage: "captions.bubble")
                .font(Theme.Font.cardTitle)
        }
        .buttonStyle(.borderless)
        .labelledHelp("Fetch subtitles for this season over the next few days")
        .confirmationDialog("Queue \(language) subtitles for \(seasonName)?", isPresented: $isAsking) {
            Button("Queue \(seasonName)") { Task { await queue(seasonId ?? "") } }
            Button("Queue Every Season") { Task { await queue("") } }
        } message: {
            Text("Episodes with no \(language) subtitle are fetched a few a day, within "
               + "OpenSubtitles' daily allowance, and each is matched to the audio "
               + "as it arrives. Progress is in Settings › Look › Subtitles.")
        }
        .alert(result ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK") { result = nil }
        }
    }

    private func queue(_ season: String) async {
        do {
            let added = try await repository.queueSubtitles(
                seriesId: seriesId, seasonId: season, language: language)
            result = added == 0
                ? "Nothing to queue — every episode already has a \(language) subtitle, or is queued."
                : "\(added) episode\(added == 1 ? "" : "s") queued."
        } catch {
            result = "The server did not queue them: \(error.localizedDescription)"
        }
    }
}
