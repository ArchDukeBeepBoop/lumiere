import SwiftUI
import LumiereKit

/// The big artwork across the top of Home — one switch for the library, one
/// for the private room.
struct HomeBackdropToggles: View {
    @AppStorage(Preference.homeShowsBackdrop.name) private var home = Preference.homeShowsBackdrop.defaultValue
    @AppStorage(Preference.homeFollowsHover.name) private var followsHover = Preference.homeFollowsHover.defaultValue
    @AppStorage(Preference.screensaverMinutes.name) private var screensaver = Preference.screensaverMinutes.defaultValue

    var body: some View {
        Toggle("Show the spotlight at the top of Home", isOn: $home)
        Text("Off, Home opens straight on its shelves. Inside the private room this is "
           + "the room's own setting, separate from the library's.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        Toggle("Change Home's background to the title pointed at", isOn: $followsHover)
        Picker("Show backdrops when idle on Home", selection: $screensaver) {
            Text("Never").tag(0)
            ForEach([2, 5, 10, 20], id: \.self) { Text("After \($0) minutes").tag($0) }
        }
    }
}
