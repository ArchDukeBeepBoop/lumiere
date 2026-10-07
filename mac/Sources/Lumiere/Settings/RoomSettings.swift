import SwiftUI
import LumiereKit

/// How the private room behaves. See `AppModel+Room`.
struct RoomSettings: View {
    @Environment(AppModel.self) private var app: AppModel?
    @AppStorage(Preference.roomRequiresUnlock.name) private var unlock = Preference.roomRequiresUnlock.defaultValue
    @AppStorage(Preference.roomLockMinutes.name) private var minutes = Preference.roomLockMinutes.defaultValue
    @AppStorage(Preference.roomUsesOwnTheme.name) private var ownTheme = Preference.roomUsesOwnTheme.defaultValue
    @AppStorage(Preference.roomBlocksCapture.name) private var blocksCapture = Preference.roomBlocksCapture.defaultValue
    @AppStorage(Preference.roomBlursCovers.name) private var blurs = Preference.roomBlursCovers.defaultValue
    @AppStorage(Preference.looksUpPrivateLibraries.name) private var looksUp = Preference.looksUpPrivateLibraries.defaultValue

    var body: some View {
        Toggle("Ask for Touch ID or your password to open the room", isOn: $unlock)
        Picker("Close the room when Lumiere has been in the background", selection: $minutes) {
            Text("At once").tag(0)
            Text("For 5 minutes").tag(5)
            Text("For 30 minutes").tag(30)
            Text("Never").tag(-1)
        }
        Toggle("Give the room its own quieter look", isOn: $ownTheme)
        Toggle("Keep the room out of screenshots and screen sharing", isOn: $blocksCapture)
        Toggle("Blur private covers until pointed at", isOn: $blurs)
        Toggle("Look up private libraries on the movie database", isOn: $looksUp)
            .onChange(of: looksUp) { Task { await app?.applyPrivacy() } }
        SettingsNote("Off, new titles in private libraries are named from their own "
                   + "filenames and never matched to anything outside — no unrelated "
                   + "artwork, no titles from somewhere else.")
    }
}
