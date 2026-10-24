import SwiftUI
import LumiereKit
import LumierePlayer

/// Audio: where it plays, when it plays, and how it sounds — the output picker
/// VLC's redesign put beside the tracks so you never leave for System Settings.
struct PlayerSidebarAudio: View {
    let model: PlayerModel
    @State private var outputs: [AudioOutputs.Device] = AudioOutputs.all()

    var body: some View {
        PlayerGroup(title: "Output") {
            PlayerPanelRow(title: "System Output", detail: nil, selected: model.audioDeviceUID == nil) {
                Task { await model.setAudioDevice(nil) }
            }
            ForEach(outputs, id: \.uid) { device in
                PlayerPanelRow(title: device.name, detail: nil, selected: model.audioDeviceUID == device.uid) {
                    Task { await model.setAudioDevice(device) }
                }
            }
        }
        .onAppear { outputs = AudioOutputs.all() }

        PlayerGroup(title: "Timing", footnote: "Sound ahead of the picture? Move it later.") {
            PlayerSliderRow(
                icon: "waveform", title: "Audio Delay",
                value: model.audioDelay, range: -5...5, step: 0.1,
                format: SidebarFormat.seconds,
                onChange: { value in Task { await model.setAudioDelay(value) } }
            )
        }

        if model.engineRef?.supportsAudioFilters ?? false {
            PlayerGroup(title: "Sound") {
                ForEach(SoundPreset.allCases) { preset in
                    PlayerPanelRow(title: preset.title, detail: nil, subtitle: preset.explanation,
                                   selected: model.soundPreset == preset) {
                        Task { await model.setSoundPreset(preset) }
                    }
                }
            }
        }

        PlayerGroup(title: "Dialogue") {
            AudioFilterRows(model: model)
        }

        PlayerGroup(title: "Volume") {
            PlayerSliderRow(
                icon: "speaker.wave.3", title: "Boost",
                value: model.volumeBoost, range: 100...200, step: 10, neutral: 100,
                format: SidebarFormat.percent,
                onChange: { value in Task { await model.setVolumeBoost(value) } }
            )
        }
    }
}
