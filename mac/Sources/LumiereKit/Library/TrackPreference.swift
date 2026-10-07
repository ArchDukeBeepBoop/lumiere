import Foundation
import GRDB

/// A remembered audio and subtitle choice.
///
/// Stored per series rather than per episode: choosing Japanese audio with English
/// subtitles on episode 1 means you want it for episode 2, and asking again every
/// episode is the behaviour this exists to remove.
///
/// Languages rather than track indices, and that distinction is the whole point. An
/// index only means something inside one file — episode 1 may carry Japanese as track
/// 2 and episode 3 as track 1 — so a remembered index eventually switches you to the
/// dub without warning.
/// The minimum a track has to tell us to be matched against a remembered language.
///
/// A protocol because `MediaTrack` lives in LumierePlayer and the kit cannot import
/// it — the dependency runs the other way. Matching is pure logic and belongs beside
/// the stored preference, so the type it works on is described rather than imported.
public protocol TrackDescribing {
    var id: Int { get }
    var language: String? { get }
    var isDefault: Bool { get }
}

/// A subtitle track, which needs more than a language to be chosen well: a release
/// routinely ships four tracks all labelled English, doing four different jobs.
public protocol SubtitleTrackDescribing: TrackDescribing {
    var title: String { get }
    var isForced: Bool { get }
}

public struct TrackPreference: Codable, Sendable, FetchableRecord, PersistableRecord {

    public static let databaseTableName = "trackPreference"

    public var key: String
    public var audioLanguage: String?
    public var subtitleLanguage: String?
    /// Distinct from a nil subtitleLanguage: "off" is a choice worth keeping, and
    /// without this flag it is indistinguishable from "never chose".
    public var subtitlesEnabled: Bool
    public var updatedAt: Date

    public init(
        key: String,
        audioLanguage: String? = nil,
        subtitleLanguage: String? = nil,
        subtitlesEnabled: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitlesEnabled = subtitlesEnabled
        self.updatedAt = updatedAt
    }

    /// Which track in *this* file matches the remembered language.
    ///
    /// Falls back to the file's default rather than to the first track: a release with
    /// commentary first would otherwise open on the commentary.
    public static func match<Track: TrackDescribing>(
        language: String?,
        in tracks: [Track]
    ) -> Int? {
        guard let language, !language.isEmpty else {
            return tracks.first(where: \.isDefault)?.id ?? tracks.first?.id
        }
        // Case- and region-insensitive: servers report "jpn", "ja" and "Japanese"
        // for the same thing depending on the file.
        let wanted = language.lowercased()
        if let exact = tracks.first(where: { $0.language?.lowercased() == wanted }) {
            return exact.id
        }
        if let prefix = tracks.first(where: {
            guard let value = $0.language?.lowercased() else { return false }
            return value.hasPrefix(String(wanted.prefix(2)))
                || wanted.hasPrefix(String(value.prefix(2)))
        }) {
            return prefix.id
        }
        // The remembered language is not in this file at all — the default is a
        // better answer than silently picking something unrelated.
        return tracks.first(where: \.isDefault)?.id ?? tracks.first?.id
    }

    /// Picks a subtitle track by language *and* by what the track is for.
    ///
    /// Language alone is not enough. An anime release carries English dialogue,
    /// English signs-and-songs, and often CC and SDH besides — all reported as
    /// "English", and whichever the muxer wrote first wins a language-only match.
    /// Landing on the signs track is the case that looks like a broken player:
    /// subtitles are on, and none of the speech is subtitled.
    public static func matchSubtitle<Track: SubtitleTrackDescribing>(
        language: String?,
        preferring kind: SubtitleKind,
        in tracks: [Track]
    ) -> Int? {
        guard !tracks.isEmpty else { return nil }

        // Narrow to the language first, since a perfect English dialogue track is
        // no use to someone who asked for Spanish.
        var candidates = tracks
        if let language, !language.isEmpty {
            let wanted = language.lowercased()
            let sameLanguage = tracks.filter {
                guard let value = $0.language?.lowercased() else { return false }
                return value == wanted
                    || value.hasPrefix(String(wanted.prefix(2)))
                    || wanted.hasPrefix(String(value.prefix(2)))
            }
            if !sameLanguage.isEmpty { candidates = sameLanguage }
        }

        let kinds = candidates.map {
            SubtitleKind.classify(title: $0.title, isForced: $0.isForced)
        }
        if let index = SubtitleKind.bestIndex(preferring: kind, among: kinds) {
            return candidates[index].id
        }
        return candidates.first(where: \.isDefault)?.id ?? candidates.first?.id
    }
}

public extension LibraryRepository {
    /// The key a preference is stored under: the series for an episode, the item
    /// itself for a film.
    nonisolated static func trackPreferenceKey(for item: ItemRecord) -> String {
        item.seriesId ?? item.id
    }

    /// The key a whole library's default is stored under.
    ///
    /// The same table, namespaced. A library default answers what a per-series memory
    /// cannot: the first time you open *anything* in Anime you already know you want
    /// Japanese audio with English subtitles, and setting that once per show — across
    /// hundreds of shows — is exactly the work being removed. A series-level
    /// preference still wins where one exists, since that is a decision made about
    /// that particular show.
    nonisolated static func libraryTrackPreferenceKey(libraryId: String) -> String {
        "library:\(libraryId)"
    }

    func trackPreference(key: String) async throws -> TrackPreference? {
        try await database.writer.read { db in try TrackPreference.fetchOne(db, key: key) }
    }

    func saveTrackPreference(_ preference: TrackPreference) async throws {
        var updated = preference
        updated.updatedAt = Date()
        let value = updated
        try await database.writer.write { db in try value.save(db) }
    }
}
