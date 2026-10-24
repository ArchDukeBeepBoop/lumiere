import AppKit
import os
import LumiereKit

/// The player's accent taken from what is playing — Apple TV's Now Playing
/// tints itself from the cover, and with Settings › Look › "Tint the player
/// from the artwork" on, so does the scrubber, the sidebar's switches and
/// every other gold-on-video mark.
///
/// Only `Color.fixedAccent` reads it: the colour drawn over video and artwork.
/// The rest of the app keeps the accent chosen in Settings, so browsing does
/// not change colour behind the film.
enum ArtworkAccent {
    /// Behind a lock rather than an actor: a colour provider resolves
    /// synchronously, from whichever thread AppKit draws on.
    private static let current = OSAllocatedUnfairLock<UInt32?>(initialState: nil)

    static var hex: UInt32? {
        guard Preference.playerTintsFromArtwork.value else { return nil }
        return current.withLock { $0 }
    }

    static func adopt(_ image: CGImage) {
        let colour = Self.colour(from: image)
        current.withLock { $0 = colour }
    }

    static func clear() { current.withLock { $0 = nil } }

    /// The artwork's average hue, made vivid and bright enough to read on
    /// black. Nil for a near-grey cover — gold beats a muddy grey.
    static func colour(from image: CGImage) -> UInt32? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Weighted by saturation, so a coloured title on a dark poster counts
        // for more than the dark around it.
        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[i]) / 255, green = Double(pixels[i + 1]) / 255, blue = Double(pixels[i + 2]) / 255
            let high = max(red, green, blue), low = min(red, green, blue)
            let w = (high - low) + 0.02
            r += red * w; g += green * w; b += blue * w; weight += w
        }
        let average = NSColor(red: r / weight, green: g / weight, blue: b / weight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.12 else { return nil }
        let vivid = NSColor(hue: hue, saturation: min(0.85, max(0.5, saturation * 1.3)), brightness: 0.9, alpha: 1)
        guard let rgb = vivid.usingColorSpace(.deviceRGB) else { return nil }
        return (UInt32(rgb.redComponent * 255) << 16) | (UInt32(rgb.greenComponent * 255) << 8) | UInt32(rgb.blueComponent * 255)
    }
}
