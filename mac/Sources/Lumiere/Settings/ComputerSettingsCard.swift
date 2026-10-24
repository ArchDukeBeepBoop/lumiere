import SwiftUI
import LumiereKit

/// Settings › On This Computer: Lumiere as the Mac's player.
struct ComputerSettingsCard: View {
    @AppStorage(Preference.remembersRecentFiles.name) private var remembersRecents
        = Preference.remembersRecentFiles.defaultValue
    @AppStorage(Preference.opensComputerWhenOffline.name) private var opensWhenOffline
        = Preference.opensComputerWhenOffline.defaultValue
    @State private var isDefault = DefaultPlayer.isDefault
    @State private var working = false

    var body: some View {
        SettingsCard(title: "On This Computer", icon: "desktopcomputer",
                     subtitle: "Files on this Mac, opened from Finder") {
            SettingsRow(label: "Default player",
                        help: "Double-clicking a video or audio file in Finder opens it in Lumiere.") {
                if isDefault {
                    Label("Lumiere", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.success)
                } else {
                    Button(working ? "Setting…" : "Make Lumiere the Default") {
                        working = true
                        Task {
                            await DefaultPlayer.makeDefault()
                            isDefault = DefaultPlayer.isDefault
                            working = false
                        }
                    }
                    .disabled(working)
                }
            }
            SettingsRow(label: "Recent files",
                        help: "Lists what you open on the On This Computer page and in File › Open Recent. Turning it off forgets the list.") {
                Toggle("Remember recent files", isOn: $remembersRecents)
                    .toggleStyle(.switch)
                    .onChange(of: remembersRecents) { if !remembersRecents { OpenRecents.clear() } }
            }
            SettingsRow(label: "Server away",
                        help: "When the server can’t be reached at launch, open on On This Computer instead of Home.") {
                Toggle("Open On This Computer", isOn: $opensWhenOffline)
                    .toggleStyle(.switch)
            }
        }
        .onAppear { isDefault = DefaultPlayer.isDefault }
    }
}
