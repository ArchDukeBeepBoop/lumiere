import Foundation

extension SettingsView {
    /// The panes, each a question people arrive with.
    ///
    /// Four became six: Home and Privacy were scattered — Home's rules across
    /// Look and Library, Privacy inside Advanced — and a setting you cannot
    /// find is one you do not have.
    enum Category: String, CaseIterable, Identifiable {
        case yours, look, home, playback, library, privacy, advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .yours: return "Your Setup"
            case .look: return "Look"
            case .home: return "Home"
            case .playback: return "Playback"
            case .library: return "Library"
            case .privacy: return "Privacy"
            case .advanced: return "Advanced"
            }
        }

        var icon: String {
            switch self {
            case .yours: return "person.crop.square"
            case .look: return "paintbrush"
            case .home: return "house"
            case .playback: return "play.rectangle"
            case .library: return "books.vertical"
            case .privacy: return "lock"
            case .advanced: return "wrench.and.screwdriver"
            }
        }

        /// One line under each pane's title saying what lives there.
        var summary: String {
            switch self {
            case .yours: return "Your libraries and folders, your account, and everything you’ve changed."
            case .look: return "Appearance, theme, titles and artwork."
            case .home: return "Its layout, what each shelf shows, and their order."
            case .playback: return "Subtitles, audio, quality, and how the player behaves."
            case .library: return "Your server, what it knows, and keeping it in order."
            case .privacy: return "Private libraries, their room, and what is shown or sent."
            case .advanced: return "Caches, hidden items, and what this machine can decode."
            }
        }
    }
}
