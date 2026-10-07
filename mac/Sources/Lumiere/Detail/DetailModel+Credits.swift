import Foundation
import LumiereKit

/// Who is credited, in the order a credits row should read.
///
/// Split from DetailModel.swift for the project's 300-line rule.
extension DetailModel {

    /// The cast first, then the people who made it, with the director last.
    ///
    /// One row for both films and series now. The old split — actors only on a
    /// film, actors plus crew on a series — meant a film page named its director
    /// nowhere at all, and the TV app's own Cast & Crew row ends with "Director"
    /// precisely because that is the credit you look for after the faces you
    /// recognise.
    ///
    /// Sorted rather than taken as the server gives it. Jellyfin returns `People`
    /// in whatever order the scraper wrote them, which for a fair number of items
    /// puts the director in the middle of the cast; "last" has to be arranged for
    /// or it does not happen. The sort is on (group, original index) rather than a
    /// bare group comparison because `sorted(by:)` is not stable in Swift, and the
    /// billing order within the cast is the one thing the server *does* get right.
    var credits: [Person] {
        // Spelled out rather than chained: as one expression the type-checker gave
        // up on it.
        var ordered: [(rank: Int, index: Int, person: Person)] = []
        for (index, person) in creditSource.enumerated() {
            ordered.append((Self.rank(of: person), index, person))
        }
        ordered.sort { left, right in
            // On (rank, original index), because `sort` is not stable in Swift and
            // billing order within the cast is the one thing the server gets right.
            left.rank == right.rank ? left.index < right.index : left.rank < right.rank
        }
        return ordered.map(\.person)
    }

    /// The payload the page is currently describing.
    ///
    /// On a series page that is the episode in the hero, not the show — the same
    /// rule the credits row follows, and for the same reason: everything below the
    /// hero is describing whatever the hero is showing. `displayedSource` and
    /// `displayedChapters` in DetailView already worked this way; the About block's
    /// own facts did not, so it reported the series' première date, the series'
    /// certificate and the series' runtime beside an episode's video and audio.
    ///
    /// Falls back to the title's own payload, which is what a film always uses.
    var displayedDetail: JellyfinItem? {
        if isSeries, let episode = heroDetail { return episode }
        return detail
    }

    /// Whose credits these are: the episode on screen, or the title itself.
    ///
    /// A series' own `People` is the standing cast, and it does not change as you
    /// move along the episode strip — so the row was answering "who is in this
    /// show" while the hero above it was showing one episode. Jellyfin credits an
    /// episode in its own right, and on this library it does so generously: of
    /// sixty cached episode payloads, fifty-six carry people, a median of nineteen
    /// each, including the guest stars that only appear in that one.
    ///
    /// Falls back to the series where an episode has none, rather than emptying the
    /// row — four of those sixty had none, and a blank Cast & Crew is worse than a
    /// slightly stale one.
    private var creditSource: [Person] {
        if isSeries, let episodePeople = heroDetail?.people, !episodePeople.isEmpty {
            return episodePeople
        }
        return detail?.people ?? []
    }

    /// The episode the credits belong to, when they are not the series'.
    ///
    /// Shown under "Cast & Crew". The row changes as you move along the strip, and a
    /// row of faces that quietly swaps itself with nothing saying why is a worse
    /// answer than the stale one it replaced.
    var creditsSubtitle: String? {
        guard isSeries, let people = heroDetail?.people, !people.isEmpty,
              let episode = heroEntry else { return nil }
        if let code = episode.item.episodeCode(compact: true) {
            return "\(code) · \(episode.item.name)"
        }
        return episode.item.name
    }

    /// Where a credit sits in the row.
    ///
    /// Faces first, then the people who made it, with the director last — the order
    /// the TV app's own row uses, because Director is the credit you look for after
    /// the faces you recognise.
    ///
    /// Anything unrecognised sorts after the named ranks rather than being dropped,
    /// which is what used to happen: the old `compactMap` returned nil for any type
    /// outside its five, so a Composer, Editor, Creator or Colorist was silently
    /// absent from a row titled "Cast & Crew". This library only produces the five
    /// today, so nothing visibly changes here — but "the scraper wrote a type we did
    /// not enumerate" is not a reason to omit someone from the credits.
    private static func rank(of person: Person) -> Int {
        switch person.type {
        case "Actor": return 0
        case "GuestStar": return 1
        case "Writer": return 2
        case "Producer": return 3
        case "Director": return 4
        default: return 5
        }
    }

    /// Who directed it, for the metadata line.
    ///
    /// Only for a film. A series has a different director most weeks, so naming
    /// one on the show's page is a fact about one episode presented as a fact
    /// about the programme.
    var directorName: String? {
        guard entry?.item.itemType == .movie else { return nil }
        return detail?.people?.first { ($0.type ?? "") == "Director" }?.name
    }
}
