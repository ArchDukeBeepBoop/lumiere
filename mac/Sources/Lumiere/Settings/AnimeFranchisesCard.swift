import SwiftUI
import LumiereKit

/// Settings › Library › Anime Franchises: which libraries are matched on
/// AniList, so every season, film and OVA of a story is gathered into one
/// collection — Fate, Monogatari, Gundam.
struct AnimeFranchisesCard: View {
    let app: AppModel
    @State private var status: AniListStatus?
    @State private var message: String?

    var body: some View {
        SettingsCard(title: "Anime Franchises", icon: "point.3.connected.trianglepath.dotted",
                     subtitle: "Every season, film and spin-off of a story, together") {
            SettingsNote("Titles in the libraries below are matched on AniList, which links each entry to its prequel, sequel and side stories. Every franchise with two or more titles here becomes a collection and stays up to date. Only titles are sent to AniList.")
            if let status {
                ForEach(status.libraries ?? []) { library in
                    Toggle(library.name, isOn: Binding(
                        get: { library.on },
                        set: { on in Task { await set(library.id, on: on) } }
                    ))
                    .toggleStyle(.switch)
                }
                if let art = status.art {
                    SettingsRow(label: "Artwork",
                                help: "A franchise wears its first entry’s poster and banner from AniList, and a show missing a poster or backdrop borrows its own entry’s. Off, a franchise shows a mosaic of its posters. Pictures you chose are never replaced.") {
                        Toggle("Key art from AniList", isOn: Binding(
                            get: { art },
                            set: { on in Task { await setArt(on) } }
                        ))
                        .toggleStyle(.switch)
                    }
                }
                if let message {
                    Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.danger)
                }
                HStack {
                    Text(status.running
                         ? "Finding franchises… \(status.matched) of \(status.checked) titles matched so far"
                         : "\(status.franchises) franchises · \(status.matched) of \(status.checked) titles matched")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Find Franchises Now") { Task { await run() } }
                        .disabled(status.running)
                }
            } else {
                Text(message ?? "Asking the server…")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
            }
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(status?.running == true ? 3 : 15))
            }
        }
    }

    private func refresh() async {
        guard let client = app.client else { return }
        do { status = try await client.aniListStatus() } catch { message = ConnectionState.message(for: error) }
    }

    private func set(_ id: String, on: Bool) async {
        guard let client = app.client, let status else { return }
        var ids = Set((status.libraries ?? []).filter(\.on).map(\.id))
        if on { ids.insert(id) } else { ids.remove(id) }
        await send { try await client.setAniListLibraries(Array(ids)) }
    }

    private func setArt(_ on: Bool) async {
        guard let client = app.client, let status else { return }
        let ids = (status.libraries ?? []).filter(\.on).map(\.id)
        await send { try await client.setAniListLibraries(ids, art: on) }
    }

    private func run() async {
        guard let client = app.client else { return }
        await send { try await client.runAniList() }
    }

    /// A change, then a fresh status; a refusal is shown, not swallowed.
    private func send(_ change: () async throws -> Void) async {
        do {
            try await change()
            message = nil
        } catch {
            message = ConnectionState.message(for: error)
        }
        await refresh()
    }
}
