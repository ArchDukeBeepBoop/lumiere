import SwiftUI
import LumiereKit

/// How often to ask the server whether anything changed. See
/// `AppModel+ChangeWatch`.
struct ChangeCheckPicker: View {
    @AppStorage(Preference.changeCheckSeconds.name) private var seconds
        = Preference.changeCheckSeconds.defaultValue

    var body: some View {
        Picker("Check the server for changes", selection: $seconds) {
            Text("Every 10 seconds").tag(10)
            Text("Every 30 seconds").tag(30)
            Text("Every 2 minutes").tag(120)
            Text("Only every 15 minutes").tag(0)
        }
        Text("Something watched on another device, or new files the server found, "
           + "reaches the home screen this quickly. Checking is a tiny request; "
           + "the library is only re-read when something actually changed. While "
           + "Lumiere is in the background it checks every two minutes at most.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
