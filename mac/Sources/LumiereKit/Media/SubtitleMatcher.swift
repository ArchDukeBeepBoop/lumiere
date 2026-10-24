import Foundation

/// Pairs a folder of subtitle files with a season's episodes — VLC's "drag a
/// subtitle onto every episode" chore, done once.
///
/// By position first: `S01E02`, `1x02`, or the bare episode number fansub
/// releases use (`[Group] Show - 02 [1080p].ass`). By name second: the
/// subtitle that is the video's own name plus a language tag. Anything left
/// unsure is left unmatched for a person to choose, rather than guessed.
///
/// Pure and string-only, so it is tested without files.
public enum SubtitleMatcher {

    public static let extensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "sup", "idx"]

    public static func isSubtitle(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// `videos` as (id, filename); returns video id → subtitle URL.
    public static func match(videos: [(id: String, name: String)], subtitles: [URL]) -> [String: URL] {
        var result: [String: URL] = [:]
        var used = Set<URL>()
        let subtitleKeys = subtitles.map { (url: $0, key: key(for: $0.lastPathComponent)) }

        for video in videos {
            guard let wanted = key(for: video.name) else { continue }
            let candidates = subtitleKeys.filter { $0.key == wanted && !used.contains($0.url) }
            // Exactly one: two subtitles for episode 2 (English and Spanish, say)
            // is a choice for a person, made by name below or by hand.
            if candidates.count == 1 {
                result[video.id] = candidates[0].url
                used.insert(candidates[0].url)
            }
        }
        for video in videos where result[video.id] == nil {
            let stem = normalised(stripExtension(video.name))
            if let hit = subtitles.first(where: { !used.contains($0) && normalised(subtitleStem($0)) == stem }) {
                result[video.id] = hit
                used.insert(hit)
            }
        }
        return result
    }

    /// The episode a filename names: "s1e2" from a structural marker, or "e2"
    /// from a lone episode number.
    public static func key(for filename: String) -> String? {
        let name = stripExtension(filename)
        if let numbering = EpisodeNumbering.parse(name: name) {
            return "s\(numbering.season)e\(numbering.episode)"
        }
        return bareEpisode(in: name).map { "e\($0)" }
    }

    /// The last 1–3 digit number standing on its own, outside brackets, that
    /// is not a resolution, a year, a version or a codec — the anime form.
    static func bareEpisode(in name: String) -> Int? {
        var outside = ""
        var depth = 0
        for character in name {
            if "[(".contains(character) { depth += 1; outside.append(" "); continue }
            if "])".contains(character) { depth = max(0, depth - 1); outside.append(" "); continue }
            outside.append(depth == 0 ? character : " ")
        }
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = outside.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
        let numbers = tokens.compactMap { token -> Int? in
            guard token.count <= 3, token.allSatisfy(\.isNumber) else { return nil }
            return Int(token)
        }
        return numbers.last
    }

    static func stripExtension(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    /// `Show.S01E02.en.srt` → `Show.S01E02`: the language tag is not the name.
    static func subtitleStem(_ url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: ".")
        if parts.count > 1, let last = parts.last, (2...3).contains(last.count), last.allSatisfy(\.isLetter) {
            stem = parts.dropLast().joined(separator: ".")
        }
        return stem
    }

    static func normalised(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Subtitle files chosen for an item, loaded each time it plays. The files
/// stay where they are; nothing is copied beside the video.
public enum SubtitleLinks {
    public static let storageKey = "subtitleLinks"

    public static func files(for itemId: String, in defaults: UserDefaults = .standard) -> [URL] {
        ((defaults.dictionary(forKey: storageKey)?[itemId] as? [String]) ?? []).map { URL(fileURLWithPath: $0) }
    }

    public static func link(_ url: URL, to itemId: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: storageKey) ?? [:]
        var list = (all[itemId] as? [String]) ?? []
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        all[itemId] = list
        defaults.set(all, forKey: storageKey)
    }

    public static func unlinkAll(from itemId: String, in defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: storageKey) ?? [:]
        all[itemId] = nil
        defaults.set(all, forKey: storageKey)
    }
}
