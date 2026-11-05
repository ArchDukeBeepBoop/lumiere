import SwiftUI
import LumiereKit

/// Settings › Playback › Music: whether a song heard to the end counts as
/// played on the server — what ranks the Music page's Top 10 Artists.
struct MusicPlaysCard: View {
    @AppStorage(Preference.countsMusicPlays.name) private var counts = Preference.countsMusicPlays.defaultValue

    var body: some View {
        SettingsCard(title: "Music", icon: "music.note") {
            SettingsRow(label: "Plays",
                        help: "A song played to its end counts as played on your server, so Top 10 Artists follows what you listen to. Off, it ranks by how much of each artist you have.") {
                Toggle("Count songs I play", isOn: $counts).toggleStyle(.switch)
            }
        }
    }
}
