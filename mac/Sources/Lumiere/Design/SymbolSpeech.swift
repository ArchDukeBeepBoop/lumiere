import Foundation

/// Words for the transport symbols, for buttons drawn from a symbol name by a
/// helper — so VoiceOver says "Next", not "forward fill".
enum SymbolSpeech {
    static func name(_ symbol: String) -> String {
        switch symbol {
        case "play.fill": return "Play"
        case "pause.fill": return "Pause"
        case "backward.fill": return "Previous"
        case "forward.fill": return "Next"
        case "shuffle": return "Shuffle"
        case "repeat", "repeat.1": return "Repeat"
        case "chevron.up": return "Open the full player"
        case "speaker.slash.fill", "speaker.slash": return "Unmute"
        default:
            return symbol.split(separator: ".").first.map { String($0).capitalized } ?? symbol
        }
    }
}
