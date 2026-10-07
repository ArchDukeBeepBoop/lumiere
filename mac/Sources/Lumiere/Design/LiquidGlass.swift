import SwiftUI
import LumiereKit

/// How the app's chrome is drawn: solid-ish frosted panels, or Liquid Glass.
///
/// Chrome only — the navigation bar, banners, the player's controls and panels,
/// the strip chevrons. Never a poster or a thumbnail: a blur samples what is
/// behind it every frame it is on screen, and a shelf of two hundred cards each
/// sampling its own backdrop is the cost this app exists to avoid. A dozen
/// chrome surfaces is a cost the window server absorbs without noticing.
enum ChromeStyle: String, CaseIterable, Identifiable {
    case solid, liquid

    static let storageKey = "chromeStyle"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Frosted"
        case .liquid: return "Liquid Glass"
        }
    }
}

/// One glass surface in the shape given.
///
/// An approximation of Liquid Glass rather than a copy, the same on every
/// macOS: a frosted material, brightened a little, with light caught along
/// the top edge, a bright rim that fades down the sides and picks up again
/// faintly at the bottom, and a dark hairline so the edge holds against a
/// pale page. Everything is a static gradient over a material the window
/// server already composites — no animation, nothing that redraws on its
/// own — so a dozen surfaces cost nothing measurable.
struct GlassFill<S: InsettableShape>: View {
    let shape: S
    var material: Material = .ultraThinMaterial
    /// A wash of colour under the glass, for a pane that must stay legible
    /// over whatever scrolls beneath it — a page one moment, dark artwork the
    /// next. Nil for chrome that only ever sits over the page.
    var tint: Color? = nil
    @AppStorage(ChromeStyle.storageKey) private var style = ChromeStyle.liquid
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if style == .liquid {
            let light = scheme == .light
            shape.fill(material)
                .overlay { if let tint { shape.fill(tint) } }
                .overlay { shape.fill(.white.opacity(light ? 0.18 : 0.05)) }
                .overlay {
                    // The sheen: light caught across the upper half.
                    shape.fill(LinearGradient(
                        stops: [
                            .init(color: .white.opacity(light ? 0.45 : 0.22), location: 0),
                            .init(color: .white.opacity(0), location: 0.5),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                }
                .overlay {
                    // The rim: brightest at the top, fading down the sides,
                    // a faint second catch at the bottom edge.
                    shape.strokeBorder(LinearGradient(
                        stops: [
                            .init(color: .white.opacity(light ? 0.95 : 0.6), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.55),
                            .init(color: .white.opacity(light ? 0.5 : 0.25), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: 1.2)
                }
                .overlay {
                    // The hairline outside it, so the pane has an edge on a
                    // pale background as well as a dark one.
                    shape.stroke(.black.opacity(light ? 0.12 : 0.35), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
        } else {
            shape.fill(material).overlay { if let tint { shape.fill(tint) } }
        }
    }
}

extension View {
    /// A glass background in the given shape. See `GlassFill`.
    func liquidGlass<S: InsettableShape>(
        _ shape: S, _ material: Material = .ultraThinMaterial, tint: Color? = nil
    ) -> some View {
        background { GlassFill(shape: shape, material: material, tint: tint) }
    }
}

/// The navigation bar in the chosen style: a floating rounded pane of glass,
/// or the flat frosted strip with a rule under it.
struct ChromeBar: ViewModifier {
    @AppStorage(ChromeStyle.storageKey) private var style = ChromeStyle.liquid

    func body(content: Content) -> some View {
        if style == .liquid {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            content
                .background {
                    GlassFill(shape: shape, material: .ultraThinMaterial)
                        // One soft shadow, on one surface: what lifts the pane
                        // off the page. Cheap at this count; never on cards.
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, Theme.Space.sm)
        } else {
            content
                .background(Theme.Palette.chrome.opacity(0.92))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.Palette.border).frame(height: 1)
                }
        }
    }
}

/// The Settings row for `ChromeStyle`.
struct ChromeStylePicker: View {
    @AppStorage(ChromeStyle.storageKey) private var style = ChromeStyle.liquid

    var body: some View {
        Picker("Controls and bars", selection: $style) {
            ForEach(ChromeStyle.allCases) { Text($0.title).tag($0) }
        }
        Text(style == .liquid
             ? "A floating glass bar, and glass on banners and player controls — never "
               + "on posters, so it costs nothing you would notice."
             : "Plain frosted panels, as before.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The Settings row for the colour theme. See `PaperTheme`.
struct ThemePicker: View {
    @AppStorage(PaperTheme.storageKey) private var theme = "standard"

    var body: some View {
        Picker("Theme", selection: $theme) {
            Text("Standard").tag("standard")
            Text("Paper").tag(PaperTheme.paper)
        }
        if theme == PaperTheme.paper {
            PaperGrainSlider()
            Text("Warm stock and ink-dark type, always light and never see-through. "
               + "Posters and the player are unchanged.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How grainy the paper is: none to heavy.
struct PaperGrainSlider: View {
    @AppStorage("paperGrain") private var strength = 0.55
    @AppStorage("paperRules") private var showsRules = true

    var body: some View {
        LabeledContent("Grain") {
            Slider(value: $strength, in: 0...1)
                .frame(width: 180)
        }
        Toggle("Rule under section titles", isOn: $showsRules)
    }
}
