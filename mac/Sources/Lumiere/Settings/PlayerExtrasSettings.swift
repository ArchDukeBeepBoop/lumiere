import SwiftUI
import LumiereKit

/// Settings › Playback rows for the player sidebar's additions: the key named
/// in on-screen messages, and the presets saved per show.
struct PlayerExtrasSettings: View {
    @AppStorage(Preference.osdShowsShortcut.name) private var showsShortcut
        = Preference.osdShowsShortcut.defaultValue
    @State private var presetCount = ShowPreset.count()

    var body: some View {
        Toggle("Show the key pressed in on-screen messages", isOn: $showsShortcut)
        SettingsNote("“Subtitles +0.1 s” comes with ⌥⌘] beside it, so a key pressed by accident can be found and undone.")

        HStack {
            Text(presetCount == 0
                 ? "No show presets saved."
                 : "\(presetCount) \(presetCount == 1 ? "show has" : "shows have") a saved preset.")
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Button("Forget All") {
                ShowPreset.removeAll()
                presetCount = 0
            }
            .disabled(presetCount == 0)
        }
        SettingsNote("Save for This Show, in the player's settings, keeps subtitle timing, look and position, audio delay, picture and sound for every episode.")
            .onAppear { presetCount = ShowPreset.count() }
    }
}
