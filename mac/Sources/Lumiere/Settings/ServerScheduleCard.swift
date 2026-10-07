import SwiftUI
import LumiereKit

/// The server's own choices, Plex-style: when something counts as watched, how
/// long Continue Watching keeps what was left, how often the disk is looked at,
/// and the hours the heavy work is allowed. Hidden on a server that is not
/// Lumiere's — Jellyfin keeps these in its own dashboard.
struct ServerScheduleCard: View {
    @Bindable var app: AppModel
    @State private var schedule: ServerSchedule?
    @State private var findingCollections = false
    @State private var collectionsLine: String?

    var body: some View {
        if let client = app.client {
            Group {
                if let schedule {
                    SettingsCard(title: "Server Schedule", icon: "clock.arrow.2.circlepath",
                                 subtitle: "What the server decides, and when it works") {
                        form(schedule, client: client)
                    }
                } else {
                    // Something to hang the load on. An empty Group is no view
                    // at all, so its .task never ran and the card never came.
                    Color.clear.frame(height: 1)
                }
            }
            .task { schedule = await client.serverSchedule() }
        }
    }

    @ViewBuilder
    private func form(_ s: ServerSchedule, client: JellyfinClient) -> some View {
        Picker("Count as watched at", selection: bind(\.watchedPercent, client)) {
            ForEach([80, 85, 90, 95, 98], id: \.self) { Text("\($0)%").tag($0) }
        }
        note("Stop past this point and it is ticked off, from any player.")
        Picker("Keep in Continue Watching", selection: bind(\.resumeWeeks, client)) {
            Text("Until finished").tag(0)
            ForEach([2, 4, 8, 13, 26, 52], id: \.self) { Text("\($0) weeks").tag($0) }
        }
        note("Something left alone longer than this is taken off the shelf. Its place is kept.")
        Picker("Look for new and changed files", selection: bind(\.scanEveryHours, client)) {
            Text("Only when asked").tag(0)
            ForEach([1, 3, 6, 12, 24], id: \.self) { Text($0 == 1 ? "Every hour" : "Every \($0) hours").tag($0) }
        }
        note("Finds files added, moved or renamed and clears ones that are gone. Waits while something plays."
             + (s.lastAutoScan.flatMap(Self.ago).map { " Last on its own \($0)." } ?? ""))
        Toggle("Share on my home network", isOn: Binding(
            get: { schedule?.listensOnNetwork ?? false },
            set: { on in
                schedule?.listensOnNetwork = on
                guard let current = schedule else { return }
                Task { if let saved = await client.setServerSchedule(current) { schedule = saved } }
            }
        ))
        note(networkLine(s))
        if s.listensOnNetwork == true {
            BlockedDevices(addresses: s.blockedAddresses ?? []) { list in
                schedule?.blockedAddresses = list
                guard let current = schedule else { return }
                Task { if let saved = await client.setServerSchedule(current) { schedule = saved } }
            }
        }
        Toggle("Make scrubbing previews", isOn: bind(\.makesPreviews, client))
        if s.makesPreviews {
            HStack {
                Picker("Between", selection: bind(\.quietFrom, client)) { hours }
                Picker("and", selection: bind(\.quietTo, client)) { hours }
            }
            note(previewLine(s))
            Button("Make Previews Now") {
                Task {
                    await client.makePreviewsNow()
                    try? await Task.sleep(for: .seconds(4))
                    schedule = await client.serverSchedule()
                }
            }
            .font(Theme.Font.caption)
        }
        Toggle("Find collections automatically", isOn: Binding(
            get: { schedule?.autoCollections ?? true },
            set: { on in
                schedule?.autoCollections = on
                guard let current = schedule else { return }
                Task { if let saved = await client.setServerSchedule(current) { schedule = saved } }
            }
        ))
        note("Every film series with two or more of your films becomes a collection, named and pictured "
           + "from the movie database — daily, room by room; 3D and My Videos are left out. Private "
           + "libraries whose lookups are off get theirs from their own films' series, if those are known.")
        Button(findingCollections ? "Finding…" : "Find Collections Now") {
            Task {
                findingCollections = true
                let result = try? await client.findCollections()
                findingCollections = false
                collectionsLine = result.map { "\($0.made) made, \($0.adopted) already there and adopted." }
                    ?? "The search did not complete."
            }
        }
        .font(Theme.Font.caption)
        .disabled(findingCollections)
        if let collectionsLine { note(collectionsLine) }
    }

    private func networkLine(_ s: ServerSchedule) -> String {
        guard s.listensOnNetwork == true else {
            return "Off: only this Mac can reach the server. Turn on for the Android app."
        }
        let addresses = (s.addresses ?? []).map { "http://\($0):8098" }
        return (addresses.isEmpty ? "No home network found right now. " :
            "Phones and TVs on this Wi-Fi find it on their own, or at "
            + addresses.joined(separator: " or ") + ". ")
            + "Nothing outside the home network is answered, and signing in is still needed."
    }

    private var hours: some View {
        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
    }

    private func previewLine(_ s: ServerSchedule) -> String {
        var parts: [String] = []
        if let made = s.previewsMade, let total = s.previewsTotal {
            parts.append("\(made) of \(total) videos have previews.")
        }
        if let working = s.working {
            parts.append("Working on \((working as NSString).lastPathComponent).")
        } else if s.waiting != nil {
            parts.append("Waiting: something is playing.")
        }
        parts.append(s.quietFrom == s.quietTo
            ? "Made at any hour nothing is playing."
            : "Made only in these hours, about fifteen seconds an episode, never while something plays.")
        return parts.joined(separator: " ")
    }

    private func bind<T>(_ key: WritableKeyPath<ServerSchedule, T>, _ client: JellyfinClient) -> Binding<T> {
        Binding(
            get: { schedule![keyPath: key] },
            set: { value in
                schedule?[keyPath: key] = value
                guard let current = schedule else { return }
                Task { if let saved = await client.setServerSchedule(current) { schedule = saved } }
            }
        )
    }

    private static func ago(_ stamp: String) -> String? {
        guard let date = ISO8601DateFormatter().date(from: stamp) else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
