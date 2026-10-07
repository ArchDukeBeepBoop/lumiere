import Foundation

/// Every setting in the app, by name, so the window can be searched.
///
/// Settings grew to six panes and thirty-odd controls, and the only way to find one
/// was to remember which pane it was filed under. That is the problem tvOS and iOS
/// solved with a search field above the sidebar, and it is the difference between a
/// window you configure once and one you actually use: nobody remembers that the
/// bitrate cap is under Playback rather than Library, but everybody can type "bit".
///
/// A hand-written list rather than something derived from the views, and the honest
/// cost is that adding a setting means adding a line here or it will not be
/// findable. A view hierarchy cannot be enumerated without building it, and a
/// search that has to build all six panes to answer a keystroke is not a search.
/// The card names below are the pane's own card titles, verbatim, so the two can be
/// compared by eye.
///
/// `keywords` carry the words someone would actually type but that do not appear on
/// screen: "dark" for Appearance, "hdr" for hardware decoding, "password" for the
/// server card. They are matched but never displayed.
struct SettingsEntry: Identifiable {
    let category: SettingsView.Category
    /// The card this setting lives in, exactly as the pane titles it.
    let card: String
    /// What the row is called, or nil when the card itself is the answer.
    var row: String?
    var keywords: [String] = []

    var id: String { "\(category.rawValue)/\(card)/\(row ?? "")" }

    var title: String { row ?? card }
    /// "Playback › Subtitles", so a result says where it will take you.
    var path: String { row == nil ? category.title : "\(category.title) › \(card)" }

    /// Everything a query is matched against, lowercased once at build time.
    fileprivate var haystack: String {
        ([card, row ?? "", category.title] + keywords)
            .joined(separator: " ")
            .lowercased()
    }
}

enum SettingsIndex {

    static let entries: [SettingsEntry] = [
        // General
        .init(category: .look, card: "Appearance", row: "Appearance",
              keywords: ["dark", "light", "theme", "auto", "mode"]),
        .init(category: .look, card: "Appearance", row: "Glass background",
              keywords: ["blur", "translucent", "transparency", "vibrancy", "frosted"]),
        .init(category: .home, card: "Home Screen Order",
              keywords: ["order", "reorder", "arrange", "shelf", "shelves", "rows",
                         "sections", "move", "first", "top", "position"]),
        .init(category: .home, card: "Home", row: "Layout",
              keywords: ["hero", "classic", "shelves", "start", "front page"]),
        .init(category: .library, card: "Metadata Providers",
              keywords: ["api", "key", "tmdb", "omdb", "imdb", "scraper", "token"]),
        .init(category: .library, card: "Server Metadata",
              keywords: ["scan", "scrape", "synopsis", "overview", "artwork", "poster",
                         "tmdb", "name", "describe", "unnamed"]),
        .init(category: .advanced, card: "Hidden from Shelves",
              keywords: ["continue watching", "next up", "unhide", "restore", "forget"]),
        .init(category: .advanced, card: "Offline Artwork",
              keywords: ["download", "posters", "cache", "aeroplane", "airplane"]),
        .init(category: .advanced, card: "Missing Artwork",
              keywords: ["fetch", "replace", "posters", "covers", "scrape"]),
        .init(category: .look, card: "Titles", row: "Show",
              keywords: ["filename", "file name", "original", "naming"]),
        .init(category: .look, card: "Titles", row: "Unwatched indicators",
              keywords: ["badge", "dot", "corner", "new", "unseen"]),
        .init(category: .look, card: "Episode stills", row: "Use the show's artwork",
              keywords: ["thumbnail", "thumb", "backdrop", "unified", "same picture"]),

        // Library
        .init(category: .library, card: "Default Languages",
              keywords: ["audio", "subtitle", "dub", "sub", "japanese", "english", "track"]),
        .init(category: .playback, card: "Subtitle Downloads", row: "Provider key",
              keywords: ["subtitle", "opensubtitles", "key", "download", "find", "sync",
                         "timing", "srt", "captions"]),
        .init(category: .playback, card: "Seeking", row: "Play files straight from disk",
              keywords: ["disk", "local", "file", "direct", "http", "stream", "seek", "fast", "path"]),
        .init(category: .playback, card: "Seeking", row: "Pause the sound while scrubbing",
              keywords: ["scrub", "drag", "seek", "pause", "audio", "sound", "stutter", "scrubber"]),
        .init(category: .playback, card: "Seeking", row: "Scroll sideways to seek",
              keywords: ["scroll", "trackpad", "wheel", "swipe", "two fingers", "seek", "gesture"]),
        .init(category: .playback, card: "Seeking", row: "Land a released scrubber",
              keywords: ["exact", "keyframe", "4k", "heavy", "precise", "landing", "lag", "slow"]),
        .init(category: .playback, card: "Seeking", row: "Arrow keys and J / L skip",
              keywords: ["arrow", "step", "skip", "seconds", "keyboard", "shift", "jump", "seek"]),
        .init(category: .playback, card: "Skipping", row: "Follow linked openings and endings",
              keywords: ["linked", "ordered chapters", "segment", "matroska", "mkv", "op", "ed",
                         "opening", "ending", "vlc", "fansub"]),
        .init(category: .playback, card: "Skipping",
              keywords: ["skip", "credits", "outro", "intro", "ending", "early", "segment",
                         "minutes", "window"]),
        .init(category: .look, card: "Details", row: "Lead the page with where you are",
              keywords: ["progress", "episode", "left", "where", "resume", "fact"]),
        .init(category: .look, card: "Details", row: "Show the original title",
              keywords: ["romaji", "japanese", "original", "native", "title"]),
        .init(category: .look, card: "Details", row: "Round ratings to one figure",
              keywords: ["rating", "decimal", "score", "stars", "round"]),
        .init(category: .look, card: "Details", row: "Order episodes by filename",
              keywords: ["episode", "order", "sort", "filename", "sequence", "ascending"]),
        .init(category: .look, card: "Details", row: "Openings before the episodes, endings after",
              keywords: ["op", "ed", "opening", "ending", "creditless", "ncop", "nced", "order"]),
        .init(category: .look, card: "Details", row: "Keep Extras apart from the seasons",
              keywords: ["extras", "specials", "season 0", "ova", "creditless"]),
        .init(category: .look, card: "Details", row: "Say why the hero was chosen",
              keywords: ["hero", "spotlight", "reason", "featured", "sentence"]),
        .init(category: .home, card: "Home", row: "Count loose videos as new",
              keywords: ["video", "loose", "3d", "my videos", "folder", "latest", "new"]),
        .init(category: .home, card: "Home Screen Order",
              keywords: ["hide", "row", "off", "latest", "shelf", "private", "order"]),
        .init(category: .home, card: "Home", row: "Show every shelf",
              keywords: ["shelves", "cap", "seven", "all", "held back", "more"]),
        .init(category: .privacy, card: "Continue Watching Artwork",
              keywords: ["backdrop", "still", "frame", "discreet", "adult", "thumbnail",
                         "continue watching", "wide", "card"]),
        .init(category: .library, card: "Library Health",
              keywords: ["health", "broken", "duplicate", "empty", "missing", "blank",
                         "thumbnail", "unnamed", "repair", "scan", "fix", "corrupt"]),
        .init(category: .library, card: "About This Library",
              keywords: ["size", "count", "statistics", "stats", "largest", "how many", "watched"]),
        .init(category: .library, card: "Removed Items",
              keywords: ["remove", "delete", "trash", "restore", "undo", "removed",
                         "hide", "get rid", "permanent", "temporary"]),
        .init(category: .home, card: "Shelf Contents",
              keywords: ["qualify", "rules", "folder", "exclude", "samples", "extras",
                         "minimum", "length", "types", "shelf", "content", "count"]),
        .init(category: .home, card: "Recently Added",
              keywords: ["recent", "new", "latest", "home", "exclude", "adult",
                         "folder", "row", "shelf"]),
        .init(category: .home, card: "Top 10 Rows",
              keywords: ["top", "ten", "10", "chart", "rank", "rating", "best",
                         "films", "series", "anime", "shelf", "home"]),
        .init(category: .privacy, card: "Private Libraries",
              keywords: ["hide", "hidden", "privacy", "private", "discreet", "nsfw",
                         "adult", "shoulder", "conceal"]),
        .init(category: .home, card: "Home", row: "Show the spotlight at the top of Home",
              keywords: ["backdrop", "hero", "banner", "spotlight", "big picture", "artwork", "private room",
                         "screensaver", "screen saver", "idle", "hide spotlight"]),
        .init(category: .privacy, card: "Private Libraries", row: "Blur private covers until pointed at",
              keywords: ["blur", "poster", "posters", "cover", "covers", "adult", "nsfw", "hide art"]),
        .init(category: .library, card: "Folders on This Mac",
              keywords: ["local", "disk", "drive", "offline", "no server", "folder",
                         "files", "usb", "external", "without jellyfin"]),
        .init(category: .library, card: "Server",
              keywords: ["jellyfin", "sign out", "log out", "address", "url", "account"]),
        .init(category: .advanced, card: "Artwork cache",
              keywords: ["disk", "space", "storage", "clear", "images"]),

        // Playback
        .init(category: .playback, card: "Subtitles", row: "Style",
              keywords: ["caption", "font", "size", "outline"]),
        .init(category: .playback, card: "Subtitles", row: "Size",
              keywords: ["bigger", "smaller", "large", "small", "font", "text", "scale"]),
        .init(category: .playback, card: "Subtitles", row: "Prefer",
              keywords: ["forced", "signs", "songs", "dialogue", "full"]),
        .init(category: .playback, card: "Subtitle Fonts",
              keywords: ["font", "typeface", "add", "install", "ttf", "otf",
                         "japanese", "cjk", "fansub", "typeset"]),
        .init(category: .playback, card: "Scrubbing Previews",
              keywords: ["trickplay", "thumbnail", "preview", "scrub", "seek",
                         "chapter", "frame", "hover", "timeline"]),
        .init(category: .playback, card: "Streaming", row: "Maximum bitrate",
              keywords: ["bandwidth", "quality", "transcode", "cap", "mbps", "data"]),
        .init(category: .playback, card: "Engine",
              keywords: ["mpv", "avplayer", "direct play", "decoder", "player"]),

        // Audio
        .init(category: .playback, card: "Volume boost", row: "Default boost",
              keywords: ["loud", "quiet", "gain", "amplify", "normalise", "normalize"]),

        // Hot keys
        .init(category: .playback, card: "In the player",
              keywords: ["keyboard", "shortcut", "keys", "space", "arrow", "seek"]),

        // This Mac
        .init(category: .advanced, card: "Hardware decoding",
              keywords: ["hevc", "h265", "av1", "hdr", "dolby vision", "gpu", "videotoolbox"])
    ]

    /// Entries matching every whitespace-separated word in the query.
    ///
    /// Every word rather than any, so typing more narrows rather than widens —
    /// "subtitle style" should find one row, not everything about subtitles plus
    /// everything about styles. Substring matching, so "bit" finds "bitrate"
    /// without anyone having to type the whole word.
    static func matches(_ query: String) -> [SettingsEntry] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            let haystack = entry.haystack
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
