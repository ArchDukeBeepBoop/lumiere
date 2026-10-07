import AppKit
import SwiftUI

/// How the menu looks: the system's own, Liquid Glass, or Paper.
///
/// All three are cheap by construction. The menu is one small window that
/// redraws on hover and on server state, and nothing here animates or samples
/// anything per frame: glass is a material with a static rim, paper is flat
/// colour. On macOS 26 the glass rows are Apple's own Liquid Glass.
enum MenuLook: String, CaseIterable, Identifiable {
    case system, glass, paper

    static let storageKey = "menuLook"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .glass: return "Glass"
        case .paper: return "Paper"
        }
    }

    static var current: MenuLook {
        MenuLook(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .glass
    }

    /// The status dot and anything else in the accent.
    var accent: Color {
        self == .paper
            ? Color(red: 0.557, green: 0.231, blue: 0.173)   // oxblood ink
            : Color(red: 0.95, green: 0.75, blue: 0.35)
    }
}

/// The paper stock behind the whole menu, when Paper is chosen.
struct MenuLookBackground: ViewModifier {
    @AppStorage(MenuLook.storageKey) private var look = MenuLook.glass

    func body(content: Content) -> some View {
        content
            .foregroundStyle(look == .paper ? Color(red: 0.165, green: 0.141, blue: 0.118) : .primary)
            .background {
                switch look {
                case .paper:
                    ZStack {
                        Color(red: 0.965, green: 0.945, blue: 0.902)
                        // The same fixed tile as Lumiere's paper: one bitmap,
                        // repeated, never redrawn.
                        Image(nsImage: MenuGrain.tile)
                            .resizable(resizingMode: .tile)
                            .blendMode(.multiply)
                            .opacity(0.55)
                    }
                case .glass:
                    // Heavier than the menu window's own frosting, so the
                    // panels above it read as separate sheets of glass.
                    Rectangle().fill(.regularMaterial)
                case .system:
                    Color.clear
                }
            }
            .preferredColorScheme(look == .paper ? .light : nil)
    }
}

/// A row's hover highlight in the chosen look.
struct MenuRowHighlight: View {
    let isOn: Bool
    @AppStorage(MenuLook.storageKey) private var look = MenuLook.glass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: look == .glass ? 9 : 6, style: .continuous)
        if !isOn {
            Color.clear
        } else if look == .glass {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.white.opacity(0.12))
                    .overlay {
                        shape.strokeBorder(LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 1)
                    }
            }
        } else if look == .paper {
            shape.fill(Color(red: 0.557, green: 0.231, blue: 0.173).opacity(0.10))
        } else {
            shape.fill(Color.primary.opacity(0.08))
        }
    }
}

/// The Look picker in Options.
struct MenuLookRow: View {
    @AppStorage(MenuLook.storageKey) private var look = MenuLook.glass

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "paintpalette")
                .font(.system(size: 13))
                .frame(width: Menu.iconColumn, alignment: .leading)
            Text("Look").font(Menu.body)
            Spacer(minLength: 8)
            Picker("", selection: $look) {
                ForEach(MenuLook.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, Menu.gutter)
        .frame(height: Menu.rowHeight)
    }
}

/// A section's panel: a sheet of glass with a lit rim in Glass, a ruled card
/// in Paper, nothing at all in System — which keeps the stock menu layout.
struct MenuPanel: ViewModifier {
    @AppStorage(MenuLook.storageKey) private var look = MenuLook.glass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch look {
        case .system:
            content
        case .glass:
            content
                .padding(.vertical, 4)
                .background {
                    if #available(macOS 26.0, *) {
                        Color.clear.glassEffect(.regular, in: shape)
                    } else {
                        shape.fill(.ultraThinMaterial)
                            .overlay {
                                shape.fill(LinearGradient(
                                    colors: [.white.opacity(0.16), .white.opacity(0)],
                                    startPoint: .top, endPoint: .center))
                            }
                            .overlay {
                                shape.strokeBorder(LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.1)],
                                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
                            }
                    }
                }
                .padding(.horizontal, 8)
        case .paper:
            content
                .padding(.vertical, 4)
                .background {
                    shape.strokeBorder(Color(red: 0.557, green: 0.231, blue: 0.173).opacity(0.22), lineWidth: 1)
                }
                .padding(.horizontal, 8)
        }
    }
}

extension View {
    func menuPanel() -> some View { modifier(MenuPanel()) }
}

/// Paper grain for the menu, made once from a fixed seed. Same recipe as
/// Lumiere's `PaperGrain`; copied rather than shared, because the two apps
/// deliberately share no code.
enum MenuGrain {
    @MainActor static let tile: NSImage = {
        let size = 192
        var pixels = [UInt8](repeating: 255, count: size * size)
        var seed: UInt32 = 0x9E37_79B9
        func next() -> UInt32 {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return seed
        }
        for i in pixels.indices {
            let r = next() % 1000
            let depth: UInt32 = r < 12 ? 42 + next() % 30 : next() % 22
            pixels[i] = UInt8(255 - depth)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }()
}

extension MenuLook {
    /// Dresses a confirmation dialog in the chosen look: Paper's stock and a
    /// light appearance, so a restore asked for from a paper menu is not a
    /// grey system sheet. System and Glass keep the standard alert.
    @MainActor
    static func style(_ alert: NSAlert) {
        guard current == .paper else { return }
        alert.window.appearance = NSAppearance(named: .aqua)
        alert.window.backgroundColor = NSColor(red: 0.965, green: 0.945, blue: 0.902, alpha: 1)
    }
}
