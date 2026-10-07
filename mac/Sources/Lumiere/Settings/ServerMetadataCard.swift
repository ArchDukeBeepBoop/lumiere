import SwiftUI
import LumiereKit

/// The server's own naming pass, in Settings.
///
/// The server scans the disk itself now, so it finds files Jellyfin never
/// catalogued — and a file found is a file with no synopsis, no year and no
/// artwork until something looks it up. This is that step, and it belongs here
/// beside the provider keys because the key is what makes it possible.
///
/// Two copies of a credential is a real cost, and it is stated rather than
/// hidden: Lumiere keeps its own key for identify, and the server needs one to
/// work with no app open. Sending it is a deliberate press.
struct ServerMetadataCard: View {
    let app: AppModel

    @State private var status: ServerMetadataStatus?
    @State private var message: String?
    @State private var isSending = false

    var body: some View {
        SettingsCard(
            title: "Server Metadata",
            icon: "sparkle.magnifyingglass",
            subtitle: "Naming what the server finds on disk",
            accessory: { accessory }
        ) {
            SettingsNote(
                "The server scans your media folders itself, so it catalogues files "
              + "nothing had indexed. A file found that way has no synopsis and no "
              + "artwork until it is looked up — this runs that lookup on the server, "
              + "with a key of its own, so it works whether or not this app is open."
            )

            if let status {
                readout(status)
            } else {
                Text("Asking the server…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }

            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await poll() }
    }

    @ViewBuilder
    private var accessory: some View {
        if let status, status.HasKey, !status.Running, status.Pending > 0 {
            Button("Name \(status.Pending)") { Task { await run() } }
                .font(Theme.Font.caption)
        } else if let status, !status.HasKey {
            Button(isSending ? "Sending…" : "Send Key to Server") {
                Task { await sendKey() }
            }
            .font(Theme.Font.caption)
            .disabled(isSending || !MetadataCredentials.hasKey(for: .tmdb))
        }
    }

    @ViewBuilder
    private func readout(_ status: ServerMetadataStatus) -> some View {
        if !status.HasKey {
            // Two different nothings, and they need different words: a server
            // with no key cannot run at all, which is not "nothing to do".
            Text(MetadataCredentials.hasKey(for: .tmdb)
                 ? "The server has no key of its own yet."
                 : "Add a TMDB key above first, then send it to the server.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        } else if status.Running {
            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small)
                Text(status.Current.map { "Naming \($0)" } ?? "Naming titles…")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            Text("\(status.Named) named · \(status.Missed) not matched")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .monospacedDigit()
        } else if status.Pending > 0 {
            Text("\(status.Pending) titles have no description or artwork.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        } else {
            Text("Everything the server has scanned is described.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func sendKey() async {
        guard let client = app.client, let token = MetadataCredentials.key(for: .tmdb) else {
            message = "No TMDB key stored in Lumiere yet."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            try await client.setServerMetadataKey(token)
            status = try? await client.serverMetadataStatus()
            message = "The server has its own copy now."
        } catch {
            message = "Couldn't store it on the server: \(error.localizedDescription)"
        }
    }

    private func run() async {
        guard let client = app.client else { return }
        message = nil
        do {
            try await client.runServerMetadata()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Polls while this pane is open, and only while it is.
    ///
    /// Faster during a pass than at rest: a settings pane left open on an idle
    /// server should not ask once a second for a number that is not moving.
    private func poll() async {
        guard let client = app.client else { return }
        while !Task.isCancelled {
            let current = try? await client.serverMetadataStatus()
            status = current
            try? await Task.sleep(for: .seconds(current?.Running == true ? 1 : 6))
        }
    }
}
