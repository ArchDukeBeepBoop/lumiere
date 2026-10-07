import SwiftUI
import LumiereKit

/// The choices that started life as requests. See `Preference`.
///
/// Every row here shipped first as behaviour and was asked for by one person.
/// Gathering them makes each one a decision the reader can reverse, and it
/// makes the app's opinions legible: the default is what was asked for, the
/// switch is the admission that it was a taste.
struct DetailsCard: View {
    @AppStorage(Preference.roundsRatings.name) private var roundsRatings
        = Preference.roundsRatings.defaultValue
    @AppStorage(Preference.showsOriginalTitle.name) private var showsOriginalTitle
        = Preference.showsOriginalTitle.defaultValue
    @AppStorage(Preference.leadsWithProgress.name) private var leadsWithProgress
        = Preference.leadsWithProgress.defaultValue
    @AppStorage(Preference.typeAwareCardLines.name) private var typeAwareCardLines
        = Preference.typeAwareCardLines.defaultValue
    @AppStorage(Preference.separatesExtras.name) private var separatesExtras
        = Preference.separatesExtras.defaultValue
    @AppStorage(Preference.explainsSpotlight.name) private var explainsSpotlight
        = Preference.explainsSpotlight.defaultValue
    @AppStorage(Preference.episodesFollowFilename.name) private var episodesFollowFilename
        = Preference.episodesFollowFilename.defaultValue
    @AppStorage(Preference.framesEpisodes.name) private var framesEpisodes
        = Preference.framesEpisodes.defaultValue

    var body: some View {
        SettingsCard(
            title: "Details",
            icon: "text.alignleft",
            subtitle: "What a title says about itself"
        ) {
            Toggle("Lead the page with where you are", isOn: $leadsWithProgress)
            caption("\"You are on episode 7 of 24\" above the metadata line, and "
                  + "\"37 minutes left\" on a film part way through. Only where it "
                  + "is true — nothing is said about something never started.")

            Divider().padding(.vertical, Theme.Space.xs)

            Toggle("Show the original title", isOn: $showsOriginalTitle)
            caption("The romaji or native name under the display name, where the "
                  + "two differ. Search has always matched it; this admits it.")

            Toggle("Studio under anime, runtime under films", isOn: $typeAwareCardLines)
            caption("The line under a tile chooses its facts by what the title is. "
                  + "Off, every tile says the year.")

            Toggle("Round ratings to one figure", isOn: $roundsRatings)
            caption("\"Rated 9\" rather than \"Rated 8.6\". A rolling average of "
                  + "strangers' votes does not carry a decimal's worth of meaning.")

            Divider().padding(.vertical, Theme.Space.xs)

            Toggle("Order episodes by filename", isOn: $episodesFollowFilename)
            caption("Episodes list in the order their files sort — \"Show - 01\", "
                  + "\"Show - 02\" — whatever a provider later called each one. Off, "
                  + "the episode number decides and the title breaks ties.")

            Toggle("Openings before the episodes, endings after", isOn: $framesEpisodes)
            caption("A season's creditless opening leads its episode list and its "
                  + "ending closes it, so playing through a season runs OP, the "
                  + "episodes, ED. Off, all creditless files sit together at the end.")

            Toggle("Keep Extras apart from the seasons", isOn: $separatesExtras)
            caption("Season 0 — OVAs, recaps, creditless openings — sits under a "
                  + "rule in the season menu, called Extras, instead of beside "
                  + "Season 1.")

            Toggle("Say why the hero was chosen", isOn: $explainsSpotlight)
            caption("The one-line reason under the featured title: what you "
                  + "abandoned, what is nearly finished, what is highly rated and "
                  + "unopened.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
