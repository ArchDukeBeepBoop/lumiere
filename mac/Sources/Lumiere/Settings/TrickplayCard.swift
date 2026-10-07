import SwiftUI
import LumiereKit

/// Scrubbing previews: whether the server has any, and asking it to make them.
///
/// The player has drawn a trickplay card since it was built — the frame that
/// follows the pointer along the scrub bar — but it can only draw one where the
/// server has generated the tile sheets, and Jellyfin does not do that by default.
/// On a library with none, every scrub showed a bare timecode and nothing said why.
///
/// The generation is asked of the server rather than done here, and that is the
/// project's rule rather than convenience: previews built on this Mac would be
/// previews only this Mac could ever see, and the whole point of a Jellyfin library
/// is that work done once serves every client. It is also genuinely expensive —
/// every file decoded end to end — which is a thing to hand to a machine that is
/// already awake for it.
struct TrickplayCard: View {
    let client: JellyfinClient?
    let repository: LibraryRepository?

    @State private var task: ScheduledTask?
    @State private var coverage: (withPreviews: Int, sampled: Int)?
    @State private var isWorking = false
    @State private var message: String?
    @State private var didCheck = false
    /// Lumiere's own server makes previews itself, on its schedule.
    @State private var ownSchedule: ServerSchedule?

    var body: some View {
        SettingsCard(
            title: "Scrubbing Previews",
            icon: "film.stack",
            subtitle: "The frame that follows the pointer along the scrub bar",
            accessory: { accessory },
            content: { content }
        )
        .task { await check() }
    }

    @ViewBuilder
    private var accessory: some View {
        if let task, client != nil {
            Button(task.isRunning ? "Running…" : "Generate on Server") {
                Task { await start(task) }
            }
            .font(Theme.Font.caption)
            .disabled(isWorking || task.isRunning)
        }
    }

    @ViewBuilder
    private var content: some View {
        if client == nil {
            SettingsNote("Sign in to a server to check.")
        } else if !didCheck {
            ProgressView().controlSize(.small)
        } else if let own = ownSchedule {
            Text("\(own.previewsMade ?? 0) of \(own.previewsTotal ?? 0) videos have previews.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
            SettingsNote("This server makes them itself"
                       + (own.makesPreviews ? ", in the hours set" : " when turned on")
                       + " under Library › Server Schedule.")
        } else if task == nil {
            SettingsNote("This server has no trickplay task, which means it predates "
                       + "the server. The player will keep showing a timecode "
                       + "while you scrub.")
        } else {
            if let coverage {
                Text(describe(coverage))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The part that is easy to lose an afternoon to: the task is a no-op on
            // any library whose own trickplay switch is off, and it reports success
            // either way.
            SettingsNote("The server generates these per library. If nothing changes "
                       + "after this runs, turn on \"Enable trickplay image "
                       + "extraction\" in the server's settings for the library, "
                       + "then run it again.")
            SettingsNote("Every file is decoded end to end, so this takes hours on a "
                       + "large library and works the server hard. It runs there, "
                       + "not here, and the results are used by every client.")
            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
        }
    }

    private func describe(_ coverage: (withPreviews: Int, sampled: Int)) -> String {
        guard coverage.sampled > 0 else { return "Nothing to sample yet." }
        if coverage.withPreviews == 0 {
            return "None of \(coverage.sampled) titles sampled have previews."
        }
        if coverage.withPreviews == coverage.sampled {
            return "All \(coverage.sampled) titles sampled have previews."
        }
        return "\(coverage.withPreviews) of \(coverage.sampled) titles sampled have previews."
    }

    // MARK: - Server

    private func check() async {
        defer { didCheck = true }
        guard let client else { return }
        if let own = await client.serverSchedule() { ownSchedule = own; return }
        task = try? await client.trickplayTask()
        coverage = await sampleCoverage(client: client)
    }

    /// Asks a handful of real files whether they have sheets.
    ///
    /// A sample rather than a count, because there is no endpoint that answers this
    /// for a library — trickplay is reported per item, so knowing for certain would
    /// mean 45,000 requests to populate one line of text. Eight is enough to tell
    /// "none at all" from "these are being made", which is the only distinction the
    /// card has to draw.
    private func sampleCoverage(client: JellyfinClient) async -> (Int, Int) {
        guard let repository else { return (0, 0) }
        let sample = (try? await repository.entries(
            types: [.movie, .episode], sort: .dateAdded, descending: true,
            limit: 8, projection: .tile
        )) ?? []
        guard !sample.isEmpty else { return (0, 0) }

        var found = 0
        for entry in sample {
            let sheets = (try? await client.trickplay(itemId: entry.item.id)) ?? [:]
            if sheets.values.contains(where: { !$0.isEmpty }) { found += 1 }
        }
        return (found, sample.count)
    }

    private func start(_ task: ScheduledTask) async {
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.startScheduledTask(id: task.id)
            message = "Started. The server will work through the library in the "
                    + "background; check back later."
            self.task = try? await client.trickplayTask()
        } catch {
            message = "Couldn't start it: \(error.localizedDescription). This needs "
                    + "an account with server management rights."
        }
    }
}
