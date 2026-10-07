import SwiftUI
import LumiereKit

/// Enhance Dialogue and Reduce Loud Sounds, at the top of the Audio tab, as
/// on Apple TV. Remembered from film to film; greyed with a note where the
/// engine playing this file cannot apply them.
struct AudioFilterRows: View {
    let model: PlayerModel
    @AppStorage(Preference.enhancesDialogue.name) private var dialogue = Preference.enhancesDialogue.defaultValue
    @AppStorage(Preference.reducesLoudSounds.name) private var quieter = Preference.reducesLoudSounds.defaultValue

    var body: some View {
        let supported = model.engineRef?.supportsAudioFilters ?? false
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Toggle("Enhance Dialogue", isOn: $dialogue)
            Toggle("Reduce Loud Sounds", isOn: $quieter)
            if !supported {
                Text("Not available for this file's player.")
                    .font(Theme.Font.trickplayTimecode)
                    .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(Theme.Font.playerRow)
        .foregroundStyle(Theme.Palette.onPlayerChrome)
        .disabled(!supported)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .onChange(of: dialogue) { apply() }
        .onChange(of: quieter) { apply() }
    }

    private func apply() {
        Task {
            await model.engineRef?.setAudioFilters(enhanceDialogue: dialogue, reduceLoud: quieter)
        }
    }
}
