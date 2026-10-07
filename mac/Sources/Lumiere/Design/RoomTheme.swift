import Foundation

/// The private room's palette: the dark theme with its colour taken out.
///
/// Not a new set of tokens — every colour in the app passes through here while
/// the room is open, and comes out as its own luminance, a shade darker and
/// faintly cool. The gold goes grey with everything else, which is the point:
/// a glance at the screen does not find the app it knows, and the eye always
/// knows which space it is in.
enum RoomTheme {
    nonisolated(unsafe) static var isOn = false

    static func map(_ hex: UInt32) -> UInt32 {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) * 0.88
        let rr = UInt32(max(0, min(255, y - 2))), gg = UInt32(max(0, min(255, y))), bb = UInt32(max(0, min(255, y + 6)))
        return (rr << 16) | (gg << 8) | bb
    }
}
