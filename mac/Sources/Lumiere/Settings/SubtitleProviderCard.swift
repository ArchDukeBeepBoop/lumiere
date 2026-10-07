import SwiftUI
import LumiereKit

/// The subtitle provider's key, and what the server can do with it.
///
/// Typed here rather than pasted into a file: a third-party credential is the
/// owner's property, and the one place it should ever appear is a field they
/// control. The server stores it beside the database at 0600, the way it
/// stores the naming pass's key, and never sends it anywhere but the
/// provider.
struct SubtitleProviderCard: View {
    let app: AppModel

    @State private var capabilities: SubtitleCapabilities?
    @State private var key = ""
    @State private var message: String?
    @State private var isSending = false
    @State private var queue: SubtitleQueueStatus?
    @State private var dailyLimit = 5
    @AppStorage(Preference.subtitleSearchLanguage.name) private var language
        = Preference.subtitleSearchLanguage.defaultValue
    @AppStorage(Preference.subtitleSyncOnDownload.name) private var syncsOnDownload
        = Preference.subtitleSyncOnDownload.defaultValue
    @AppStorage(Preference.subtitleSyncTrustPercent.name) private var trustPercent
        = Preference.subtitleSyncTrustPercent.defaultValue
    @AppStorage(Preference.subtitleSyncMaxShiftSeconds.name) private var maxShift
        = Preference.subtitleSyncMaxShiftSeconds.defaultValue

    var body: some View {
        SettingsCard(
            title: "Subtitle Downloads",
            icon: "captions.bubble",
            subtitle: "Finding a subtitle the file does not have"
        ) {
            SettingsNote(
                "With an OpenSubtitles key the player can search for a subtitle "
              + "mid-film and load it without losing your place. Whatever it "
              + "finds is checked against the audio and shifted to match — a "
              + "release cut for a different master is often half a minute out, "
              + "and one number fixes the whole episode."
            )

            if let capabilities, capabilities.hasKey {
                LabeledContent("Provider key", value: "Stored on the server")
                Button("Forget the key") { Task { await send("") } }
                    .font(Theme.Font.caption)
            } else {
                SecureField("OpenSubtitles API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button(isSending ? "Sending…" : "Send Key to Server") {
                    Task { await send(key) }
                }
                .font(Theme.Font.caption)
                .disabled(isSending || key.trimmingCharacters(in: .whitespaces).isEmpty)
                caption("Free at opensubtitles.com — register, then Consumers → "
                      + "New Consumer. The key is stored on the server only.")
            }

            timing
            queueRows

            if let capabilities, !capabilities.canSync {
                Text("The server has no ffmpeg, so it can find subtitles but not "
                   + "check their timing.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await load() }
    }

    /// What a search asks for, and how a sync behaves.
    @ViewBuilder
    private var timing: some View {
        LabeledContent("Search language") {
            TextField("en", text: $language)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
        caption("A two-letter code, or several separated by commas: en, ja.")

        Toggle("Match timing to the audio on download", isOn: $syncsOnDownload)
        Stepper(value: $trustPercent, in: 10...90, step: 5) {
            LabeledContent("Apply a sync when at least", value: "\(trustPercent)% sure")
        }
        caption("A right match usually scores 50–90%; the wrong episode's "
              + "subtitle scores about 25%. Lower applies more shifts and "
              + "risks a wrong one; higher asks you more often.")
        Stepper(value: $maxShift, in: 5...300, step: 5) {
            LabeledContent("Look up to", value: "\(maxShift) s either way")
        }
        caption("How far out a subtitle may be and still be found. Wider "
              + "catches a different master; narrower is faster and less "
              + "likely to lock onto a coincidence.")
    }

    /// The server's subtitle queue: what is waiting, and how many a day.
    @ViewBuilder
    private var queueRows: some View {
        if let queue {
            LabeledContent("Subtitle queue", value: "\(queue.waiting) episodes waiting, \(queue.done) fetched"
                + (queue.failed > 0 ? ", \(queue.failed) not found" : ""))
            Stepper(value: $dailyLimit, in: 1...200) {
                LabeledContent("Fetch per day", value: "\(dailyLimit) (\(queue.doneToday) today)")
            }
            .onChange(of: dailyLimit) { _, limit in
                Task { try? await app.client?.setSubtitleDailyLimit(limit) }
            }
            ForEach(queue.shows ?? []) { show in
                LabeledContent(show.series) {
                    Text("\(show.done) of \(show.done + show.waiting + show.failed) done"
                         + (show.failed > 0 ? ", \(show.failed) not found" : ""))
                        .monospacedDigit()
                }
                .font(Theme.Font.caption)
            }
            if queue.failed > 0 {
                Button("Try the \(queue.failed) Not Found Again") {
                    Task {
                        _ = try? await app.client?.retryFailedSubtitles()
                        await load()
                    }
                }
                .font(Theme.Font.caption)
            }
            caption("Queue a season from its page with Queue Subtitles…. OpenSubtitles "
                  + "allows about 5 downloads a day with a key alone and more with a paid "
                  + "account; set this to what your account allows.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func load() async {
        capabilities = try? await app.client?.subtitleCapabilities()
        if let status = try? await app.client?.subtitleQueueStatus() {
            queue = status
            dailyLimit = status.dailyLimit
        }
    }

    private func send(_ value: String) async {
        guard let client = app.client else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await client.setSubtitleKey(value)
            key = ""
            message = value.isEmpty ? "The server has forgotten the key." : "Key stored."
            await load()
        } catch {
            message = "The server did not take the key: \(error.localizedDescription)"
        }
    }
}
