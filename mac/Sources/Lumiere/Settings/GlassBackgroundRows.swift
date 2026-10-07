import SwiftUI
import LumiereKit

/// The see-through window's switch and tint — or, on Paper, why there is none.
struct GlassBackgroundRows: View {
    @Binding var isGlass: Bool
    /// How much canvas sits over the blur (0.35…0.95). The slider shows its
    /// inverse, how much of the desktop comes through.
    @Binding var opacity: Double
    @AppStorage(PaperTheme.storageKey) private var theme = "standard"

    var body: some View {
        if theme == PaperTheme.paper {
            caption("Paper is opaque stock, so the window is never see-through while "
                  + "it is the theme. Switch to Standard for the glass background.")
        } else {
            Toggle("Glass background", isOn: $isGlass)
            caption("Blurs the desktop through the window, the way the sidebar and "
                  + "the menu bar already do. Turn it off for a flat, opaque "
                  + "background — worth doing if you read subtitles or synopses "
                  + "over a busy wallpaper.")
            if isGlass {
                HStack(spacing: Theme.Space.sm) {
                    Text("Tint").font(Theme.Font.caption)
                    // Inverted, for real this time: right is more glass. The
                    // old slider claimed to be and was not, so its knob sat at
                    // the far left while its label read the maximum.
                    Slider(
                        value: Binding(get: { 1 - opacity }, set: { opacity = 1 - $0 }),
                        in: 0.05...0.65
                    )
                    Text("\(Int(((1 - opacity) * 100).rounded()))%")
                        .font(Theme.Font.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textMuted)
                        .frame(width: 40, alignment: .trailing)
                }
                caption("How much of the desktop comes through. Past about two "
                      + "thirds the wallpaper starts competing with poster art.")
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
