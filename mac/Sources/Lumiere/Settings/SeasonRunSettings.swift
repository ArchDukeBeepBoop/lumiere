import SwiftUI
import LumiereKit

/// Whether Next and Previous cross from one season to the next. See
/// `SeasonNeighbours`.
struct SeasonRunSettings: View {
    @AppStorage(Preference.continuesAcrossSeasons.name) private var continues
        = Preference.continuesAcrossSeasons.defaultValue
    @AppStorage(Preference.includesSpecialsInOrder.name) private var specials
        = Preference.includesSpecialsInOrder.defaultValue
    @AppStorage(Preference.watchedAtCredits.name) private var watchedAtCredits
        = Preference.watchedAtCredits.defaultValue
    @AppStorage(Preference.offersRecapSkip.name) private var offersRecapSkip
        = Preference.offersRecapSkip.defaultValue
    @AppStorage(Preference.autoSkipsIntros.name) private var autoSkipsIntros
        = Preference.autoSkipsIntros.defaultValue
    @AppStorage(Preference.playsNextAutomatically.name) private var playsNext
        = Preference.playsNextAutomatically.defaultValue
    @AppStorage(Preference.showsUpNextStage.name) private var upNextStage
        = Preference.showsUpNextStage.defaultValue
    @AppStorage(Preference.stillWatchingAfter.name) private var stillWatching
        = Preference.stillWatchingAfter.defaultValue

    var body: some View {
        Toggle("Carry on into the next season", isOn: $continues)
        Text("The last episode of a season offers the first of the next, and "
           + "Previous goes back across the boundary too.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        if continues {
            Toggle("Include specials in the running order", isOn: $specials)
        }
        Toggle("Play the next episode automatically", isOn: $playsNext)
        Toggle("At the credits, show Up Next full screen", isOn: $upNextStage)
        if playsNext {
            Picker("Ask \u{201C}Still watching?\u{201D}", selection: $stillWatching) {
                Text("Never").tag(0)
                ForEach([2, 3, 4, 5, 8], id: \.self) { Text("After \($0) episodes").tag($0) }
            }
        }
        Toggle("Offer to skip recaps and previews", isOn: $offersRecapSkip)
        Toggle("Skip a season's intro automatically once I have skipped it three times",
               isOn: $autoSkipsIntros)
        Toggle("Count as watched once the credits start", isOn: $watchedAtCredits)
        Text("Stop during the end credits and the episode is ticked off, rather than "
           + "waiting in Continue Watching with a minute of titles left. Without "
           + "detected credits, the last 5% counts.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
