import Foundation

/// The player's letter keys, which you can change in Settings › Playback ›
/// Keyboard. VLC hides its hotkeys four levels into advanced preferences; the
/// redesign brought them out, and so does this.
///
/// Only the single-letter keys move. Space, the arrows, the digits and Esc are
/// the same in every player on every platform, and stay put.
enum PlayerKeyBinding: String, CaseIterable, Identifiable {
    case playPause, back, forward, mute, fullScreen, info, pictureInPicture
    case subtitleEarlier, frameBack, frameForward

    static let storageKey = "playerKeyBindings"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .back: return "Skip back"
        case .forward: return "Skip forward"
        case .mute: return "Mute"
        case .fullScreen: return "Full screen"
        case .info: return "Info, audio and subtitles"
        case .pictureInPicture: return "Picture in Picture"
        case .subtitleEarlier: return "Subtitles earlier (⇧ for later)"
        case .frameBack: return "Frame back · slower"
        case .frameForward: return "Frame forward · faster"
        }
    }

    var defaultKey: String {
        switch self {
        case .playPause: return "k"
        case .back: return "j"
        case .forward: return "l"
        case .mute: return "m"
        case .fullScreen: return "f"
        case .info: return "i"
        case .pictureInPicture: return "p"
        case .subtitleEarlier: return "z"
        case .frameBack: return ","
        case .frameForward: return "."
        }
    }

    /// The key bound now.
    var key: String {
        (UserDefaults.standard.dictionary(forKey: Self.storageKey)?[rawValue] as? String) ?? defaultKey
    }

    func playerKey(shift: Bool) -> PlayerKey {
        switch self {
        case .playPause: return .k
        case .back: return .j
        case .forward: return .l
        case .mute: return .m
        case .fullScreen: return .f
        case .info: return .info
        case .pictureInPicture: return .pictureInPicture
        case .subtitleEarlier: return shift ? .subtitleLater : .subtitleEarlier
        case .frameBack: return .comma
        case .frameForward: return .period
        }
    }

    /// The binding a typed character belongs to.
    static func binding(for character: String) -> PlayerKeyBinding? {
        let character = character.lowercased()
        return allCases.first { $0.key == character }
    }

    /// Keys a binding may not take: the fixed ones, digits, and anything that
    /// is not one printable character.
    static func isAllowed(_ character: String) -> Bool {
        guard character.count == 1, let scalar = character.unicodeScalars.first else { return false }
        return !CharacterSet.whitespacesAndNewlines.contains(scalar)
            && !CharacterSet.decimalDigits.contains(scalar)
            && !CharacterSet.controlCharacters.contains(scalar)
    }

    /// Binds `character` to this action; whatever had it takes this one's old
    /// key, so no two actions ever share a key.
    func bind(_ character: String) {
        let character = character.lowercased()
        var all = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        if let other = Self.binding(for: character), other != self { all[other.rawValue] = key }
        all[rawValue] = character
        UserDefaults.standard.set(all, forKey: Self.storageKey)
    }

    static func resetAll() { UserDefaults.standard.removeObject(forKey: storageKey) }

    /// As the shortcuts list writes a key.
    static func display(_ character: String) -> String { character.uppercased() }
}
