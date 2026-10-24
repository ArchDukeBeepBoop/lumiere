import SwiftUI
import LumiereKit
import LumierePlayer

/// Video: the frame (shape, zoom, turn, mirror), then the picture's colour,
/// then quality. Every change lands on the picture beside the sidebar.
struct PlayerSidebarVideo: View {
    let model: PlayerModel

    var body: some View {
        if !model.supportsVideoAdjustments {
            Text("This file plays on the system player, which can't reshape or adjust the picture. These controls are available for files mpv plays.")
                .font(Theme.Font.playerRow)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                .padding(Theme.Space.sm)
        } else {
            frame
            colour
            quality
        }
    }

    private var frame: some View {
        PlayerGroup(title: "Frame") {
            Menu {
                ForEach(AspectOverride.allCases) { aspect in
                    Button(aspect.title) { Task { await model.setAspect(aspect) } }
                }
            } label: {
                PlayerActionRow(icon: "aspectratio", title: "Aspect Ratio",
                                trailing: model.aspectOverride.title, action: {})
                    .allowsHitTesting(false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            PlayerSliderRow(
                icon: "plus.magnifyingglass", title: "Zoom",
                value: model.picture.zoom * 100, range: 100...200, step: 5, neutral: 100,
                format: SidebarFormat.percent,
                onChange: { value in update { $0.zoom = value / 100 } }
            )
            PlayerSliderRow(
                icon: "arrow.up.and.down", title: "Vertical Shift",
                value: model.verticalShift * 100, range: -20...20, step: 1,
                format: { Int($0) == 0 ? "None" : String(format: "%+d%%", Int($0)) },
                onChange: { value in Task { await model.setVerticalShift(value / 100) } }
            )
            PlayerActionRow(icon: "rotate.right", title: "Rotate",
                            detail: "A quarter turn clockwise each press.",
                            trailing: model.picture.rotation == 0 ? "None" : "\(model.picture.rotation)°") {
                update { $0.rotateClockwise() }
            }
            PlayerSwitchRow(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                            title: "Flip Horizontally", isOn: Binding(
                                get: { model.flipHorizontal },
                                set: { _ in Task { await model.toggleFlip(horizontal: true) } }))
            PlayerSwitchRow(icon: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                            title: "Flip Vertically", isOn: Binding(
                                get: { model.flipVertical },
                                set: { _ in Task { await model.toggleFlip(horizontal: false) } }))
        }
    }

    private var colour: some View {
        PlayerGroup(title: "Picture") {
            slider("sun.max", "Brightness", \.brightness)
            slider("circle.lefthalf.filled", "Contrast", \.contrast)
            slider("drop", "Saturation", \.saturation)
            slider("camera.filters", "Gamma", \.gamma)
            if model.picture != .neutral {
                PlayerActionRow(icon: "arrow.counterclockwise", title: "Reset Picture") {
                    Task { await model.setPicture(.neutral) }
                }
            }
        }
    }

    private var quality: some View {
        PlayerGroup(title: "Quality",
                    footnote: "Deinterlace smooths the combed lines of old TV recordings and DVDs.") {
            PlayerSwitchRow(icon: "line.3.horizontal", title: "Deinterlace", isOn: Binding(
                get: { model.picture.deinterlace },
                set: { on in update { $0.deinterlace = on } }))
            ForEach(UpscalingMode.allCases) { mode in
                PlayerPanelRow(title: "Upscaling: \(mode.title)", detail: nil, subtitle: mode.explanation,
                               selected: model.upscaling == mode) {
                    Task { await model.setUpscaling(mode) }
                }
            }
            PlayerSwitchRow(icon: "lightbulb.min", title: "Ambient Mode",
                            detail: "Dims everything around the picture.",
                            isOn: Binding(get: { model.ambientMode }, set: { model.ambientMode = $0 }))
        }
    }

    private func slider(_ icon: String, _ title: String,
                        _ key: WritableKeyPath<PictureAdjustments, Int>) -> some View {
        PlayerSliderRow(
            icon: icon, title: title,
            value: Double(model.picture[keyPath: key]), range: -100...100, step: 1,
            format: SidebarFormat.signed,
            onChange: { value in update { $0[keyPath: key] = Int(value) } }
        )
    }

    private func update(_ change: (inout PictureAdjustments) -> Void) {
        var picture = model.picture
        change(&picture)
        Task { await model.setPicture(picture) }
    }
}
