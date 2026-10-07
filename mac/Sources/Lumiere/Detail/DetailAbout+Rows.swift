import Foundation
import LumiereKit

/// What the About block actually lists, and in what order.
///
/// Split from DetailAbout.swift for the project's 300-line rule. Deliberately
/// string-building only — no views — so the order of the block can be read in one
/// place without stepping over layout.
extension DetailAbout {

    struct AboutRow {
        let label: String
        let value: String
    }

    /// Released, Rated, Runtime, Studio, then the file's own languages.
    ///
    /// The TV app's order, and it is the order of the questions: when is it from,
    /// who is it for, how long is it, who made it, and can I watch it in a
    /// language I speak. Everything is dropped rather than shown empty — a library
    /// this varied has items with almost none of it, and a column of "—" says only
    /// that the scraper failed.
    ///
    /// Read from the detail payload first and the cached row second. The cached
    /// row is what renders instantly on open; the payload is richer but arrives a
    /// moment later, so this must not be written to depend on only one of them.
    var rows: [AboutRow] {
        var rows: [AboutRow] = []
        if let released { rows.append(AboutRow(label: "Released", value: released)) }
        if let rating = displayed?.officialRating ?? model.item?.officialRating {
            rows.append(AboutRow(label: "Rated", value: rating))
        }
        if let runtime { rows.append(AboutRow(label: "Runtime", value: runtime)) }
        if let studios { rows.append(AboutRow(label: "Studio", value: studios)) }
        if let video { rows.append(AboutRow(label: "Video", value: video)) }
        if let audio { rows.append(AboutRow(label: "Audio", value: audio)) }
        if let subtitles { rows.append(AboutRow(label: "Subtitles", value: subtitles)) }
        rows.append(contentsOf: fileRows)
        // Last, after the file's own facts. The rows above answer "what is this and
        // can I play it", which is what the block is opened for; the crew is what
        // you read once you have decided.
        rows.append(contentsOf: crewRows)
        return rows
    }

    /// What the file is called and where it lives, for folder libraries only.
    ///
    /// In `3D` and `My Videos` there is no scraper, so the filename is the identity
    /// and the folder is how the collection is organised — a season's worth of loose
    /// files, a franchise, a rip source. That is the question these pages are opened
    /// to answer, and nothing on them answered it: the header shows a tidied name and
    /// the About block listed only what a scraper would have found, which for these
    /// items is nothing.
    ///
    /// Absent everywhere else. In a scraped library the path is an implementation
    /// detail of the server's disk layout and says nothing about the film.
    ///
    /// The extension stays here, unlike on a tile: the question being asked is what
    /// the file is actually called.
    var fileRows: [AboutRow] {
        // The cached row rather than the payload: `libraryId` is a column this app
        // stamps during sync and Jellyfin's item has no equivalent, so only the
        // cached side can answer which library the file belongs to. Its `path` is
        // the same string either way.
        guard let item = model.item,
              let libraryId = item.libraryId, folderLibraryIds.contains(libraryId),
              let path = item.path ?? displayed?.path, !path.isEmpty
        else { return [] }

        var rows = [AboutRow(label: "File", value: (path as NSString).lastPathComponent)]
        // The whole folder path, not just the last component. On this library the
        // shape is `/Volumes/…/3D/Clips/Quiet House` — the mount prefix repeats on
        // every row and says nothing, but the branch under it is how the collection
        // is organised, and cutting to the last component alone would lose that.
        // "Location" is a path; showing half of one answers a different question.
        let folder = (path as NSString).deletingLastPathComponent
        if !folder.isEmpty {
            rows.append(AboutRow(label: "Folder", value: folder))
        }
        return rows
    }

    /// The payload this block is describing — the episode on a series page.
    ///
    /// See `DetailModel.displayedDetail`. The video and audio rows were already the
    /// episode's, because `displayedSource` resolves that way; the facts above them
    /// were the series', so an episode's picture sat under the show's première date,
    /// the show's certificate and the show's runtime.
    private var displayed: JellyfinItem? { model.displayedDetail }

    /// Every crew credit, one row per role.
    ///
    /// The Cast & Crew shelf is faces, and a face is a poor way to read a crew: it
    /// puts eight portraits on screen to say four names you wanted as text. So the
    /// people who made it are listed here as well, by role — which is also the only
    /// place a Composer or an Editor was ever going to be legible.
    ///
    /// Grouped in the order `credits` already sorted them, so Director leads and
    /// anything the scraper named that this app does not enumerate still appears,
    /// under its own label, rather than being dropped for being unfamiliar.
    ///
    /// Actors and guest stars are excluded: they are the shelf above, and a series
    /// with thirty of them would bury every other row.
    private var crewRows: [AboutRow] {
        var order: [String] = []
        var namesByRole: [String: [String]] = [:]

        for person in model.credits {
            guard let role = person.type, role != "Actor", role != "GuestStar",
                  let name = person.name, !name.isEmpty else { continue }
            if namesByRole[role] == nil { order.append(role) }
            // Deduplicated: a scraper that credits someone twice for one role — a
            // writer of both the story and the teleplay — should be named once.
            if !(namesByRole[role] ?? []).contains(name) {
                namesByRole[role, default: []].append(name)
            }
        }

        return order.map { role in
            let names = namesByRole[role] ?? []
            return AboutRow(
                label: Self.roleLabel(role, count: names.count),
                value: Self.nameList(names)
            )
        }
    }

    /// How many names a role prints before it summarises the rest.
    ///
    /// Four, taken from the library rather than chosen: of the crew roles across
    /// every cached payload here, 66% carry one name, 96% carry four or fewer. The
    /// cap therefore leaves almost every row exactly as it was and only bites on the
    /// outliers — the anime production committees, where Producer runs to ten and
    /// thirteen names and turns a fact into a paragraph.
    private static let namesPerRole = 4

    /// The names, and an honest count of the ones not shown.
    ///
    /// Not a silent `prefix`. The cast shelf used to stop at twenty with nothing
    /// indicating a row had been cut, which is the worse failure — a list that ends
    /// without saying it ended reads as complete. "and 9 more" costs four words and
    /// tells the truth.
    static func nameList(_ names: [String]) -> String {
        guard names.count > namesPerRole else { return names.joined(separator: ", ") }
        let shown = names.prefix(namesPerRole).joined(separator: ", ")
        return "\(shown) and \(names.count - namesPerRole) more"
    }

    /// "Director", "Writers", "Directors of Photography".
    ///
    /// Jellyfin's person types are camel-case single words, so a plural is an "s"
    /// on the end for all of them, and splitting the camel case is what turns
    /// `GuestStar` into something a person would write.
    static func roleLabel(_ role: String, count: Int) -> String {
        var spaced = ""
        for character in role {
            if character.isUppercase, !spaced.isEmpty { spaced.append(" ") }
            spaced.append(character)
        }
        return count > 1 ? spaced + "s" : spaced
    }

    /// The episode's own runtime where there is one.
    ///
    /// `model.runtimeText` reads the series, whose `RunTimeTicks` is a nominal
    /// episode length rather than the length of the file you are about to play.
    private var runtime: String? {
        guard let seconds = displayed?.runtimeSeconds ?? model.item?.runtimeSeconds
        else { return nil }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// The full première date where the server has one, the production year where
    /// it does not. A day is more useful than a year and never less.
    private var released: String? {
        if let date = displayed?.premiereDate ?? model.item?.premiereDate {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        if let year = model.detail?.productionYear ?? model.item?.productionYear {
            return String(year)
        }
        return nil
    }

    private var studios: String? {
        // Three at most. Jellyfin lists every production company a scraper found,
        // which for a co-production runs to eight names nobody reads past.
        // The episode's, then the series'. An episode rarely carries studios of its
        // own, and "who made this show" is still the right answer when it does not.
        let source = displayed?.studios?.isEmpty == false
            ? displayed?.studios : model.detail?.studios
        let names = (source ?? []).compactMap(\.name).prefix(3)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// "4K · Dolby Vision · HEVC" — what the picture is, not how it is encoded.
    /// The bit depth, the frame rate and the software-decode warning stay in the
    /// panel below, where they answer a different question.
    private var video: String? {
        guard let stream = source?.videoStream else { return nil }
        var parts: [String] = []
        if let resolution = MediaSummary.resolutionLabel(
            width: stream.width, height: stream.height
        ) {
            parts.append(resolution)
        }
        if let range = MediaSummary.rangeLabel(
            for: stream, dolbyVisionSupported: capabilities.dolbyVision
        ) {
            parts.append(range)
        }
        if let codec = stream.codec { parts.append(MediaSummary.normalise(codec: codec)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "English (Dolby Digital 5.1), Japanese (AAC 2.0)".
    ///
    /// Language first, because that is what the row is being read for; the format
    /// in brackets after it, because on a file with two English tracks it is the
    /// only thing telling them apart. Capped at four — a remux with twelve dubs is
    /// a list, not a fact.
    private var audio: String? {
        let described = (source?.audioStreams ?? []).prefix(4).map { stream -> String in
            let format = [
                stream.codec.map(MediaSummary.normalise(codec:)) ?? "",
                MediaSummary.channelLabel(for: stream),
            ].filter { !$0.isEmpty }.joined(separator: " ")
            let name = Self.languageName(stream.language) ?? "Undetermined"
            return format.isEmpty ? name : "\(name) (\(format))"
        }
        return described.isEmpty ? nil : described.joined(separator: ", ")
    }

    /// Languages only, and each one once. Subtitles are where a file is at its
    /// most repetitive — full, forced and SDH tracks of the same language — and
    /// the question being asked here is "are there English subtitles", not "how
    /// many are there".
    private var subtitles: String? {
        var seen = Set<String>()
        var names: [String] = []
        for stream in source?.subtitleStreams ?? [] {
            let name = Self.languageName(stream.language) ?? "Undetermined"
            if seen.insert(name).inserted { names.append(name) }
        }
        return names.isEmpty ? nil : names.prefix(8).joined(separator: ", ")
    }

    /// Jellyfin stores ISO 639-2 codes — "eng", "jpn". `Locale` resolves those to
    /// a reader's own language names; a code it does not know is shown as it came
    /// rather than dropped, since an unnamed track is still a track.
    static func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}
