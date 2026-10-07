import SwiftUI
import LumiereKit

/// Posters and details: the movie database key, given once and kept by both
/// this Mac and the server, which names what it scans with no app open.
struct SetupDetailsPage: View {
    let app: AppModel
    @State private var token = ""
    @State private var hasKey = MetadataCredentials.key(for: .tmdb) != nil
    @State private var message: String?
    @State private var schedule: ServerSchedule?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SetupHeading(title: "Posters & details",
                         detail: "Lumiere fills in posters, backdrops, synopses, cast and film series from The Movie Database (TMDB). It needs a free key of your own — it stays on this Mac and your server, and is never shown again.")
            if hasKey {
                Label("A TMDB key is stored.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.Palette.accent)
            }
            Text("1. Make a free account at themoviedb.org.\n2. In its Settings › API, request a key.\n3. Copy the “API Read Access Token” — the long one — and paste it here.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField(hasKey ? "Replace the stored key" : "API Read Access Token", text: $token)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { Task { await save() } }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message {
                Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            if let current = schedule {
                Divider().padding(.vertical, Theme.Space.sm)
                Toggle("Gather films into collections automatically", isOn: Binding(
                    get: { current.autoCollections ?? true },
                    set: { on in
                        var next = current
                        next.autoCollections = on
                        Task { schedule = await app.client?.setServerSchedule(next) ?? schedule }
                    }))
                .toggleStyle(.switch)
                SettingsNote("Every film series in your libraries becomes a collection, room by room — the Private Room’s stay in it. 3D and home videos are left alone.")
            }
            SettingsNote("No key? Everything still works: titles come from the filenames, and pictures from the videos themselves.")
        }
        .task { schedule = await app.client?.serverSchedule() }
    }

    private func save() async {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try MetadataCredentials.store(value, for: .tmdb)
            try await app.client?.setServerMetadataKey(value)
            try? await app.client?.runServerMetadata()
            token = ""
            hasKey = true
            message = "Saved. The server is filling in your libraries now."
        } catch {
            message = "Couldn’t save it: \(error.localizedDescription)"
        }
    }
}

/// A few choices worth making on day one. Everything else waits in Settings.
struct SetupPreferencesPage: View {
    @AppStorage("glassBackground") private var isGlass = true
    @AppStorage(Preference.homeShowsBackdrop.name) private var backdrop = Preference.homeShowsBackdrop.defaultValue
    @AppStorage(Preference.playsNextAutomatically.name) private var playsNext = Preference.playsNextAutomatically.defaultValue
    @AppStorage(Preference.autoSkipsIntros.name) private var skipsIntros = Preference.autoSkipsIntros.defaultValue
    @AppStorage(Preference.mergesUpNext.name) private var upNext = Preference.mergesUpNext.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SetupHeading(title: "Make it yours",
                         detail: "A few choices to start with. Each one, and many more, can be changed any time in Settings — and Settings › Your Setup lists everything you’ve changed.")
            row("Let the desktop show through the window", "Frosted glass behind the app, as macOS does.", $isGlass)
            row("Spotlight on Home", "A featured title across the top of Home.", $backdrop)
            row("One Up Next row", "Next episodes, series to continue and seasons to finish, together.", $upNext)
            row("Play the next episode automatically", "When one ends, the next begins after a short countdown.", $playsNext)
            row("Skip intros by themselves", "Openings marked in the file are skipped without a click.", $skipsIntros)
        }
    }

    private func row(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.body)
                Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
            }
        }
        .toggleStyle(.switch)
    }
}

/// The last step: the scan's progress, and what to try first.
struct SetupReadyPage: View {
    let app: AppModel
    @State private var scan: ServerScanStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SetupHeading(title: "You’re ready",
                         detail: "Lumiere is reading your folders. Titles appear as they’re found; posters follow as they’re looked up.")
            if let scan, scan.Running {
                HStack(spacing: Theme.Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(scan.Library ?? "your libraries") — \(scan.Files.formatted()) files, \(scan.Added.formatted()) new")
                        .font(Theme.Font.caption)
                }
            } else if let scan {
                Label("Scan finished: \(scan.Files.formatted()) files.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Palette.accent)
            }
            Text("Worth knowing").font(Theme.Font.cardTitle).padding(.top, Theme.Space.md)
            tip("⌘F", "Search everything.")
            tip("⌘3 – ⌘9", "Jump straight to a library.")
            tip("I", "Info about whatever is highlighted, or playing.")
            tip("P", "Picture in Picture while watching.")
            tip("⌘,", "Settings. “Your Setup” there brings this guide back.")
        }
        .task {
            while !Task.isCancelled {
                scan = try? await app.client?.serverScanStatus()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func tip(_ keys: String, _ text: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(keys).font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 6))
            Text(text).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
