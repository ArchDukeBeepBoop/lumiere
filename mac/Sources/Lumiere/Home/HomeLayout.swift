import Foundation

enum HomeLayout: String, CaseIterable, Identifiable {
    /// Infuse's own arrangement, and the default: wide continue cards, then
    /// Next Up, then a shelf per library.
    case classic
    /// Full-bleed spotlight backdrop, then shelves. Sells the media.
    case hero
    /// Compact continue row, then a dense poster wall. More items per screen.
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .hero: return "Hero"
        case .compact: return "Compact"
        }
    }

    var explanation: String {
        switch self {
        case .classic:
            return "Wide continue-watching cards, then a row per library."
        case .hero:
            return "A large backdrop of highly-rated titles, then rows beneath."
        case .compact:
            return "A small continue-watching row, then a dense grid of posters."
        }
    }
}
