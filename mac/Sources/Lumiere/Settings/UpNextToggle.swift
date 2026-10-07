import SwiftUI
import LumiereKit

/// Whether Next Up, Continue the Series and Finish the Season share one row.
struct UpNextToggle: View {
    @AppStorage(Preference.mergesUpNext.name) private var merges = Preference.mergesUpNext.defaultValue

    var body: some View {
        Toggle("One “Up Next” row", isOn: $merges)
        Text("The next episode of each show, the next film of each film series, and "
           + "the shows you have nearly finished, in one row. Off, they are three "
           + "rows you can place separately. Takes effect when Home next refreshes.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        ShuffleToggle()
    }
}

/// Whether Shuffle shows its pick first or plays it at once.
struct ShuffleToggle: View {
    @AppStorage(Preference.shufflePlaysAtOnce.name) private var atOnce = Preference.shufflePlaysAtOnce.defaultValue

    var body: some View {
        Toggle("Shuffle plays its pick at once", isOn: $atOnce)
        Text("Off, Shuffle shows the title it chose, with Play, Another and Open.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
