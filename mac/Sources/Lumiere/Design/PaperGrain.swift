import SwiftUI
import LumiereKit
import AppKit

/// The tooth of the Paper theme: a faint grain over the page.
///
/// One 192-point tile of noise, made once and repeated, multiplied into the
/// page colour beneath everything else. It never animates and never redraws
/// on its own — the compositor tiles a single small bitmap — so the texture
/// costs a few hundred kilobytes once and nothing per frame. It sits behind
/// the content, so posters and type are never drawn through it.
enum PaperGrain {

    /// Made on first use, from a fixed seed: the same paper every launch.
    @MainActor static let tile: NSImage = makeTile(size: 192)

    static func makeTile(size: Int) -> NSImage {
        var pixels = [UInt8](repeating: 255, count: size * size)
        var seed: UInt32 = 0x9E37_79B9
        func next() -> UInt32 {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return seed
        }
        for i in pixels.indices {
            // Mostly near-white, with the occasional darker fleck: fine grain
            // with a little fibre in it, rather than even static.
            let r = next() % 1000
            let depth: UInt32 = r < 12 ? 42 + next() % 30 : next() % 22
            pixels[i] = UInt8(255 - depth)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}

/// The grain layer, drawn only when Paper is the theme.
struct PaperGrainLayer: View {
    @AppStorage(PaperTheme.storageKey) private var theme = "standard"
    /// How strong the grain is. Settings › Look.
    @AppStorage("paperGrain") private var strength = 0.55

    var body: some View {
        if theme == PaperTheme.paper, strength > 0 {
            Image(nsImage: PaperGrain.tile)
                .resizable(resizingMode: .tile)
                .blendMode(.multiply)
                .opacity(strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A short ink rule under a section heading, on Paper only — the mark a
/// printed page puts under a heading, and most of what makes Paper read as
/// a page rather than the standard layout recoloured. Settings › Look.
struct PaperRule: View {
    @AppStorage(PaperTheme.storageKey) private var theme = "standard"
    @AppStorage("paperRules") private var showsRules = true

    var body: some View {
        if theme == PaperTheme.paper, showsRules {
            Rectangle()
                .fill(Theme.Palette.accent.opacity(0.55))
                .frame(width: 36, height: 1.5)
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
    }
}
