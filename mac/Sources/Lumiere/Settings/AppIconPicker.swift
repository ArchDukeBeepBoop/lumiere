import SwiftUI
import LumiereKit

/// The Settings row for the app icon.
///
/// Shown as the icons themselves rather than as a list of names, which is the
/// one place in this pane where a picture is plainly better than a word:
/// nobody chooses an icon from the word "Aperture". It is also cheap — both
/// previews are drawn by the same code that renders the icns, so there are no
/// assets to ship and none to fall out of step.
struct AppIconPicker: View {
    @AppStorage(AppIconChoice.storageKey) private var choice = AppIconChoice.aperture.rawValue

    private var selected: AppIconChoice {
        AppIconChoice(rawValue: choice) ?? .aperture
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("App Icon")
                .font(Theme.Font.body)

            HStack(spacing: Theme.Space.md) {
                ForEach(AppIconChoice.allCases) { option in
                    Button {
                        choice = option.rawValue
                        option.apply()
                    } label: {
                        preview(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == selected ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }

            Text(selected.explanation)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preview(_ option: AppIconChoice) -> some View {
        let isSelected = option == selected
        return VStack(spacing: Theme.Space.xs) {
            Image(nsImage: option.image(size: 56))
                .resizable()
                .frame(width: 56, height: 56)
                .overlay {
                    // The selection ring sits outside the artwork rather than
                    // over it: an icon is being judged here, and a border drawn
                    // across its corners changes the thing you are judging.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: 2)
                        .padding(-4)
                }
            Text(option.title)
                .font(Theme.Font.caption)
                .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textMuted)
        }
        .contentShape(Rectangle())
    }
}
