import SwiftUI
import LumiereKit

/// The Playback, Audio, Hot Keys and This Mac panes.
///
/// Split out of SettingsView.swift to keep it under the project's 300-line limit.
/// These four are read-mostly — three of them are almost entirely reference — so
/// they group naturally away from the panes that hold real state.
extension SettingsView {
    @ViewBuilder
    /// Playback, which now includes what used to be Audio and Hot Keys.
    ///
    /// Volume boost and the keyboard grammar were their own panes. Both answer
    /// "how does the player behave", which is one question, and splitting it
    /// three ways meant looking in three places to change how a film plays.
    var playbackForm: some View {
        SettingsCard(
            title: "Seeking",
            icon: "slider.horizontal.below.rectangle",
            subtitle: "How the picture follows a drag, a key, or two fingers"
        ) {
            Toggle("Play files straight from disk", isOn: $playsFromDisk)
            caption("The server is on this Mac, and so is the library. Where "
                  + "a file can be read directly it is opened directly, instead "
                  + "of streamed back over HTTP — a seek costs about a quarter "
                  + "as much. Off, or where the volume is not readable, the "
                  + "server streams it. Remuxes and transcodes always stream.")

            Toggle("Pause the sound while scrubbing", isOn: $pausesWhileScrubbing)
            caption("The picture follows the cursor either way. With the sound "
                  + "running it stutters through every keyframe passed over; "
                  + "paused, the drag is silent and playback resumes on release.")

            Toggle("Scroll sideways to seek", isOn: $scrollSeeks)
            caption("Two fingers left or right on the trackpad, or a tilting "
                  + "wheel, moves the picture — right is forward, as in mpv. "
                  + "About a fifth of a second per point of travel; a whole swipe "
                  + "is a minute.")

            SeasonRunSettings()

            Toggle("Remember a flipped picture for the whole show", isOn: $remembersFlip)
            caption("Flip the picture once from the player's settings and every "
                  + "episode of that show opens the same way. Off, each file "
                  + "starts unflipped.")

            Picker("Land a released scrubber", selection: $seekLanding) {
                ForEach(SeekLanding.allCases) { Text($0.title).tag($0.rawValue) }
            }
            caption("An exact landing decodes forward from the keyframe before "
                  + "the spot, which on a 4K film in software is a second or more "
                  + "— the picture lands, then jumps again. Heavy means wider "
                  + "than 1440p. Arrow keys always land on a keyframe, as in mpv.")

            Divider().padding(.vertical, Theme.Space.xs)

            Stepper("Arrow keys and J / L skip \(seekStepSeconds) s",
                    value: $seekStepSeconds, in: 1...120)
            Stepper("Shifted arrows skip \(seekLongStepSeconds) s",
                    value: $seekLongStepSeconds, in: 5...600, step: 5)
            caption("Holding a key coalesces the presses into one seek that "
                  + "lands exactly when the key comes up.")
        }
        .resettable(SettingsDefaults.player)

        SettingsCard(
            title: "Skipping",
            icon: "forward.end",
            subtitle: "When the player believes a credits mark"
        ) {
            Toggle("Follow linked openings and endings", isOn: $followsLinkedChapters)
            caption("Some releases ship the opening and ending once, as their own "
                  + "files, and each episode borrows them by segment link — the "
                  + "way VLC plays them as one piece. On, the player follows the "
                  + "links; off, the episode plays as the file alone. Episodes "
                  + "whose linked files are missing are counted in the sync panel.")

            Divider().padding(.vertical, Theme.Space.xs)

            Stepper(
                "Believe credits that begin within the last \(creditsWindowMinutes) min",
                value: $creditsWindowMinutes, in: 1...30
            )
            caption("Your server's detector marks the ending theme, and it is "
                  + "wrong often enough to matter — on this library, fourteen "
                  + "hundred marks begin four to thirteen minutes before the "
                  + "end. Skip Credits appears only for a mark that begins this "
                  + "close to the end, or within the last 15% of a long file, "
                  + "whichever is more.")
        }

        SettingsCard(
            title: "Subtitles",
            icon: "captions.bubble",
            subtitle: "Which English track to reach for when several are offered"
        ) {
            Picker("Style", selection: $subtitleStyle) {
                ForEach(SubtitleStyle.all) { Text($0.title).tag($0.id) }
            }
            caption(SubtitleStyle.style(id: subtitleStyle).detail
                  + " Applies to SRT and VTT tracks. An ASS or SSA script keeps its "
                  + "own typesetting — overriding that would move a sign off the "
                  + "thing it labels and flatten work a group did deliberately.")

            Picker("Size", selection: $subtitleSize) {
                ForEach(SubtitleSize.allCases) { Text($0.title).tag($0.rawValue) }
            }
            caption("Scales whichever style is chosen above, rather than replacing "
                  + "it — a subtitle stays the same fraction of the picture on a "
                  + "720p file and a 4K one. Unlike the style, this does reach an "
                  + "ASS or SSA script: it changes the scale and nothing else, so a "
                  + "typeset sign stays where the group put it, just larger. It can "
                  + "also be changed mid-film from the player's gear menu.")

            Picker("Prefer", selection: $preferredSubtitleKind) {
                ForEach(SubtitleKind.allCases) { Text($0.title).tag($0.rawValue) }
            }
            caption("A release routinely carries four tracks all labelled English: "
                  + "the dialogue, a signs-and-songs track for watching the dub, and "
                  + "often CC and SDH besides. Matching on language alone lands on "
                  + "whichever the muxer wrote first, and when that is signs-only the "
                  + "player looks broken — subtitles on, none of the speech "
                  + "subtitled. Asking for dialogue falls back to CC or SDH where a "
                  + "release ships no clean track, since those carry the speech too.")
        }

        SubtitleFontsCard()

        TrickplayCard(client: app.client, repository: app.repository)

        SettingsCard(title: "Streaming", icon: "antenna.radiowaves.left.and.right") {
            Picker("Maximum bitrate", selection: $maxBitrateMbps) {
                Text("Unlimited").tag(0.0)
                Text("40 Mbps").tag(40.0)
                Text("20 Mbps").tag(20.0)
                Text("10 Mbps").tag(10.0)
                Text("4 Mbps").tag(4.0)
                // Below the 4 Mbps floor this picker used to stop at, which was
                // above the average bitrate of this library — so no cap on offer
                // could ever bite, and the transcode path was unreachable from the
                // UI. These are also the caps that mean something away from a LAN:
                // 2 Mbps is a hotel connection, 1 Mbps is tethered.
                Text("2 Mbps").tag(2.0)
                Text("1 Mbps").tag(1.0)
            }
            caption(maxBitrateMbps == 0
                    ? "No cap — the right choice on a LAN, and the only setting under "
                    + "which a file can direct play. Any cap forces the server to re-encode."
                    : "Files above this are re-encoded by the server, which costs it CPU.")
        }

        SettingsCard(title: "Engine", icon: "cpu") {
            LabeledContent("mpv", value: app.mpvVersion ?? "Not loaded")
            Text(app.mpvAvailable
                 ? "Handles the containers and codecs AVFoundation cannot open, which "
                 + "on a real library is most of them."
                 : "Without mpv, anything AVFoundation cannot open has to be "
                 + "transcoded by the server.")
                .font(Theme.Font.caption)
                .foregroundStyle(app.mpvAvailable ? Theme.Palette.textMuted : Theme.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var audioForm: some View {
        SettingsCard(title: "Volume boost", icon: "speaker.wave.3") {
            Picker("Default boost", selection: $defaultVolumeBoost) {
                Text("Off (100%)").tag(100.0)
                Text("125%").tag(125.0)
                Text("150%").tag(150.0)
                Text("200%").tag(200.0)
            }
            caption("Amplifies quiet sources past unity. Only the mpv engine can do "
                  + "this; AVFoundation clamps at 100%.")
        }
    }

    /// A reference rather than a rebinding UI. Remapping is real work, and a dead
    /// editor would be worse than an honest list.
    var hotKeysForm: some View {
        SettingsCard(title: "In the player", icon: "keyboard") {
            ForEach(hotKeys, id: \.0) { key, action in
                LabeledContent(action) {
                    Text(key)
                        .font(Theme.Font.timecode)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }

    /// Computed, so the two step rows say what the Seeking card set.
    private var hotKeys: [(String, String)] { [
        ("Space", "Play or pause"),
        ("← / →", "Back or forward \(seekStepSeconds) seconds"),
        ("⇧← / ⇧→", "Back or forward \(seekLongStepSeconds) seconds"),
        ("⌥← / ⌥→", "Previous or next chapter"),
        ("Scroll ← / →", "Seek with the trackpad or wheel"),
        ("J / K / L", "Back, pause, forward"),
        ("↑ / ↓", "Volume up or down"),
        ("M", "Mute"),
        ("F", "Full screen"),
        (", / .", "Slower or faster"),
        ("Z / ⇧Z", "Subtitles earlier or later"),
        ("Esc", "Close the player"),
    ] }

    /// Shows what this machine can actually do, so a surprise later — a file that
    /// tone-maps, or one that decodes in software — is explainable rather than
    /// mysterious.
    var thisMacForm: some View {
        SettingsCard(title: "Hardware decoding", icon: "cpu") {
            LabeledContent("Architecture", value: app.capabilities.architecture)
            LabeledContent("H.264", value: app.capabilities.hardwareH264 ? "Hardware" : "Software")
            LabeledContent("HEVC", value: app.capabilities.hardwareHEVC ? "Hardware" : "Software")
            LabeledContent("VP9", value: app.capabilities.hardwareVP9 ? "Hardware" : "Software")
            LabeledContent("AV1", value: app.capabilities.hardwareAV1 ? "Hardware" : "Software")
            LabeledContent(
                "Dolby Vision",
                value: app.capabilities.dolbyVision ? "Native" : "Tone-mapped to HDR10"
            )
        }
    }
}
