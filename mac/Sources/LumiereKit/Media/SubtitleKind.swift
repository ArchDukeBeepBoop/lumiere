import Foundation

/// What an English subtitle track actually is.
///
/// A release commonly carries four English tracks and calls them all "English".
/// Picking by language alone gets you whichever the muxer put first, which on anime
/// is very often the signs-and-songs track — a handful of on-screen captions and
/// karaoke, and none of the dialogue. The player then looks broken, when what
/// happened is that it chose a track doing a different job.
///
/// So the track's *title* is read, because that is where releases say what a track
/// is. Pure and string-only, and deliberately conservative: an unlabelled track is
/// `.dialogue`, since the common case by far is a single ordinary subtitle stream
/// with nothing written on it.
public enum SubtitleKind: String, Sendable, CaseIterable, Identifiable {
    /// Full subtitles for the spoken script. What almost everyone wants.
    case dialogue
    /// Signs, on-screen text and song lyrics only, for watching a dub.
    case signsAndSongs
    /// Closed captions: dialogue plus sound description, usually verbatim.
    case closedCaptions
    /// Subtitles for the deaf and hard of hearing.
    case sdh
    /// Commentary, forced narrative, or anything else named but unrecognised.
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dialogue: return "Dialogue"
        case .signsAndSongs: return "Signs & Songs"
        case .closedCaptions: return "Closed Captions"
        case .sdh: return "SDH"
        case .other: return "Other"
        }
    }

    /// Ranked by how likely each is to be the one someone wants, so a preference of
    /// "dialogue" can fall back sensibly when a release has no such track. SDH and
    /// CC carry the dialogue too — they are worse than a clean track but far better
    /// than signs-only, which carries none of it.
    public var dialogueRank: Int {
        switch self {
        case .dialogue: return 0
        case .closedCaptions: return 1
        case .sdh: return 2
        case .other: return 3
        case .signsAndSongs: return 4
        }
    }

    /// Classifies a track from its title and flags.
    ///
    /// Matched on whole words rather than substrings: "designs" contains "signs",
    /// and a track called "Song of the Sea (English)" is not a signs track.
    public static func classify(
        title: String?,
        isForced: Bool = false,
        isHearingImpaired: Bool = false
    ) -> SubtitleKind {
        // Flags first — they are structured data, where a title is a convention.
        if isHearingImpaired { return .sdh }

        let words = Set(
            (title ?? "")
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        guard !words.isEmpty else {
            // A forced track with no title is nearly always signs: that is what
            // "forced" is for on a release with an English dub.
            return isForced ? .signsAndSongs : .dialogue
        }

        if words.contains("sdh") || words.contains("hi") { return .sdh }
        if words.contains("cc") || words.contains("captions") { return .closedCaptions }

        // "Signs & Songs", "Signs/Songs", "S&S", "Songs & Signs", "Signs only".
        if words.contains("signs") || words.contains("karaoke") { return .signsAndSongs }
        // "S&S" and "S+S" tokenise to a lone "s", so they need the raw title.
        let compact = (title ?? "").lowercased().filter { !$0.isWhitespace }
        if compact == "s&s" || compact == "s+s" { return .signsAndSongs }

        if words.contains("dialogue") || words.contains("dialog")
            || words.contains("full") || words.contains("subtitles") {
            return .dialogue
        }
        if words.contains("commentary") || words.contains("forced") { return .other }

        // A named track that says nothing recognisable — a fansub group's name,
        // usually — is far more likely to be the dialogue than anything else.
        return isForced ? .signsAndSongs : .dialogue
    }

    /// Picks the best track for a preferred kind, given what a file actually holds.
    ///
    /// Returns the index into `kinds`, or nil when there is nothing to choose. The
    /// fallback is by `dialogueRank` rather than by order, so asking for dialogue on
    /// a release that only ships CC gets the CC track instead of the signs one.
    public static func bestIndex(
        preferring preferred: SubtitleKind, among kinds: [SubtitleKind]
    ) -> Int? {
        guard !kinds.isEmpty else { return nil }
        if let exact = kinds.firstIndex(of: preferred) { return exact }
        guard preferred == .dialogue else { return nil }
        return kinds.indices.min {
            kinds[$0].dialogueRank < kinds[$1].dialogueRank
        }
    }
}
