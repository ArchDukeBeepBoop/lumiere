import SwiftUI
import LumiereKit

/// Enhance Dialogue and Reduce Loud Sounds, the Sound column of the Audio
/// menu, as on Apple TV. Remembered from film to film; greyed with a note
/// where the engine playing this file cannot apply them.
struct AudioFilterRows: View {
    let model: PlayerModel
    @AppStorage(Preference.enhancesDialogue.name) private var dialogue = Preference.enhancesDialogue.defaultValue
    @AppStorage(Preference.reducesLoudSounds.name) private var quieter = Preference.reducesLoudSounds.defaultValue

    var body: some View {
        let supported = model.engineRef?.supportsAudioFilters ?? false
        VStack(alignment: .leading, spacing: 2) {
            PlayerSwitchRow(icon: "waveform.and.mic", title: "Enhance Dialogue", isOn: $dialogue)
            PlayerSwitchRow(icon: "speaker.wave.1", title: "Reduce Loud Sounds", isOn: $quieter)
            if !supported {
                Text("Not available for this file's player.")
                    .font(Theme.Font.playerDetail)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                    .padding(.horizontal, Theme.Space.sm)
            }
        }
        .disabled(!supported)
        .opacity(supported ? 1 : 0.55)
        .onChange(of: dialogue) { apply() }
        .onChange(of: quieter) { apply() }
    }

    private func apply() {
        Task {
            await model.engineRef?.setAudioFilters(enhanceDialogue: dialogue, reduceLoud: quieter)
        }
    }
}
