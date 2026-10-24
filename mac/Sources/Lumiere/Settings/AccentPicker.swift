import SwiftUI
import LumiereKit

/// Settings › Look › Accent: a row of swatches, as System Settings draws its
/// own accent colour choice.
struct AccentPicker: View {
    @AppStorage(AccentTheme.storageKey) private var choice = AccentTheme.gold.rawValue
    @AppStorage(Preference.playerTintsFromArtwork.name) private var tintsFromArtwork
        = Preference.playerTintsFromArtwork.defaultValue
    @AppStorage(Preference.showsWhatsNew.name) private var showsWhatsNew = Preference.showsWhatsNew.defaultValue

    var body: some View {
        swatches
        SettingsRow(label: "In the player",
                    help: "The scrubber and the player’s highlights take their colour from the poster of what’s playing, as Apple TV’s Now Playing does.") {
            Toggle("Tint the player from the artwork", isOn: $tintsFromArtwork).toggleStyle(.switch)
        }
        SettingsRow(label: "After an update",
                    help: "A card of the three biggest changes, the first time Lumiere opens after an update.") {
            Toggle("Show What’s New", isOn: $showsWhatsNew).toggleStyle(.switch)
        }
    }

    private var swatches: some View {
        SettingsRow(label: "Accent colour",
                    help: "Buttons, the scrubber, selections and highlights. Gold is Lumiere’s own.") {
            HStack(spacing: Theme.Space.sm) {
                ForEach(AccentTheme.allCases) { accent in
                    let selected = choice == accent.rawValue
                    Button { choice = accent.rawValue } label: {
                        Circle()
                            .fill(Color(hex: accent.swatch))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Theme.Palette.borderStrong, lineWidth: 0.5))
                            .overlay {
                                if selected {
                                    Circle().fill(Theme.Palette.canvas).frame(width: 7, height: 7)
                                }
                            }
                            .padding(2)
                            .overlay(Circle().strokeBorder(selected ? Theme.Palette.textSecondary : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .labelledHelp(accent.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
