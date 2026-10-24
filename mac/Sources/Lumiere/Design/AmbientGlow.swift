import SwiftUI
import LumiereKit

/// Light from the artwork, spilling in from the window's edges — the way
/// visionOS lets a film light the room around it. Shown only in the Private
/// Room's dark theme, where there is darkness for it to fall on, and only
/// while Settings › Privacy › "Glow from the artwork" is on.
///
/// The colours come from an 8-point decode of the backdrop: two averages,
/// top and bottom, so a sunset reads warm above and dark below. No full
/// decode, so it costs nothing next to the hero it sits behind.
struct AmbientGlow: View {
    let pipeline: ImagePipeline
    let request: ImageRequest?
    @AppStorage(Preference.roomAmbientGlow.name) private var isOn = Preference.roomAmbientGlow.defaultValue
    @State private var colours: (top: Color, bottom: Color)?

    var body: some View {
        ZStack {
            if RoomTheme.isOn, isOn, let colours {
                RadialGradient(colors: [colours.top.opacity(0.42), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 620)
                RadialGradient(colors: [colours.top.opacity(0.30), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 520)
                RadialGradient(colors: [colours.bottom.opacity(0.32), .clear],
                               center: .bottom, startRadius: 0, endRadius: 700)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(Theme.Motion.ambient, value: colours?.top)
        .task(id: request) {
            guard RoomTheme.isOn, isOn, let request else { colours = nil; return }
            let tiny = ImageRequest(serverURL: request.serverURL, itemId: request.itemId, kind: request.kind,
                                    tag: request.tag, displayWidth: 8, aspectRatio: 16 / 9, screenScale: 1)
            guard let image = await pipeline.image(for: tiny) else { return }
            colours = Self.average(image.cgImage)
        }
    }

    /// The mean colour of the top and bottom halves.
    static func average(_ image: CGImage) -> (top: Color, bottom: Color)? {
        let width = 4, height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func row(_ y: Int) -> Color {
            var r = 0.0, g = 0.0, b = 0.0
            for x in 0..<width {
                let i = (y * width + x) * 4
                r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2])
            }
            let n = Double(width) * 255
            // Lifted a little: an average of a dark film is nearly black, and
            // a glow of black is no glow.
            return Color(red: min(1, r / n * 1.4), green: min(1, g / n * 1.4), blue: min(1, b / n * 1.4))
        }
        // CoreGraphics rows run bottom-up.
        return (top: row(1), bottom: row(0))
    }
}
