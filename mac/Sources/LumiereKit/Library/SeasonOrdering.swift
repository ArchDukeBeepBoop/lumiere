import Foundation

/// The two orderings a season list needs, and why neither is the query's.
///
/// Split from LibraryRepository+Detail.swift for the project's 300-line rule, and
/// they belong together: both correct the same thing, which is that SQL can only
/// sort by a stored key and the key an episode stores says nothing useful when the
/// scraper never gave it numbers.
public extension Array where Element == LibraryEntry {
    /// Seasons in the order a person expects.
    ///
    /// Two fixes in one. Ordering by title is what the query does, and alphabetically
    /// "Season 10" comes before "Season 2" — so any show with ten or more seasons was
    /// listed wrongly. And Jellyfin numbers its specials season 0, which sorts it
    /// first, ahead of the episodes it is a supplement to.
    ///
    /// Sorted by season number with 0 moved to the end, so specials sit after the
    /// real seasons rather than in front of them. Seasons with no number keep to the
    /// back, ordered by name, since there is nothing better to say about them.
    var orderedAsSeasons: [LibraryEntry] {
        sorted { left, right in
            let a = left.item.indexNumber
            let b = right.item.indexNumber
            switch (a, b) {
            case (nil, nil):
                return left.item.name.localizedStandardCompare(right.item.name) == .orderedAscending
            case (nil, _): return false
            case (_, nil): return true
            case (let a?, let b?):
                // 0 is Specials: last, not first.
                if a == 0 { return false }
                if b == 0 { return true }
                return a < b
            }
        }
    }
}

public extension Array where Element == LibraryEntry {
    /// Specials by name, where an ordinary season goes by number.
    ///
    /// A numbered season has a real order: episode 2 follows episode 1 and the story
    /// depends on it. A specials season does not. It is a bag of OVAs, picture
    /// dramas, recaps and shorts, and the numbers on them are whatever the scraper
    /// assigned in whatever order it happened to list them — not an order anyone
    /// watches in. What you actually do with specials is look for one by name.
    ///
    /// `localizedStandardCompare`, so "Special 2" precedes "Special 10".
    ///
    /// Creditless material is untouched here: `CreditlessClassifier.ordered` runs
    /// afterwards and keeps openings and endings at the end, which is where they
    /// belong however the rest is arranged.
    ///
    /// Read off the entries rather than passed in, because the season row is not
    /// always there — specials dropped loose in a series folder are episodes with
    /// no season at all.
    ///
    /// `parentIndexNumber ?? 0`, and the `??` is the whole fix. The first attempt
    /// tested `== 0` and did nothing, because Jellyfin does not write a season
    /// number onto an episode it could not place: on a real library every one of
    /// K-ON!'s sixteen `URA-ON!!` shorts and five of Tanya's specials carry null,
    /// not zero. Null and zero mean the same thing here — "no season of its own" —
    /// and treating them differently is what left the list untouched.
    ///
    /// The second clause handles the seasons those shorts are actually filed under.
    /// Jellyfin put K-ON!'s inside Season 1 beside the numbered episodes, so the
    /// list is not all specials and the rule above rightly declines it — but an
    /// episode with no number sorts on a key of all zeroes, so those eight sat in
    /// front of episode 1 in whatever order the table held them. They now go to the
    /// end, in name order, which is both where a supplement belongs and the only
    /// order they have.
    var orderedAsSpecials: [LibraryEntry] {
        guard !isEmpty else { return self }
        let byName: (LibraryEntry, LibraryEntry) -> Bool = {
            $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
        }

        if allSatisfy({ ($0.item.parentIndexNumber ?? 0) == 0 }) {
            return sorted(by: byName)
        }

        let unnumbered = filter { $0.item.indexNumber == nil }
        guard !unnumbered.isEmpty else { return self }
        return filter { $0.item.indexNumber != nil } + unnumbered.sorted(by: byName)
    }
}


public extension Array where Element == LibraryEntry {

    /// Episodes in the order the files say.
    ///
    /// The list came back ordered by `sortName`, which after a scrape is the
    /// episode's *title* — so a numbered season with metadata read
    /// alphabetically: "The Night of the Comet" before "Pilot". A person
    /// naming files `Show - 01.mkv`, `Show - 02.mkv` has already said what the
    /// order is, and that order survives whatever a provider later calls each
    /// one.
    ///
    /// - Parameter byFilename: the preference. On, the file's own name decides,
    ///   compared the way Finder compares — `10` after `9`. Off, the episode
    ///   number decides and the title breaks ties; an episode with no number
    ///   goes last, in title order.
    func orderedAsEpisodes(byFilename: Bool) -> [LibraryEntry] {
        let finder: (String, String) -> Bool = {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        if byFilename {
            return sorted { a, b in
                let left = a.item.path.map { ($0 as NSString).lastPathComponent } ?? a.item.name
                let right = b.item.path.map { ($0 as NSString).lastPathComponent } ?? b.item.name
                return finder(left, right)
            }
        }
        return sorted { a, b in
            switch (a.item.indexNumber, b.item.indexNumber) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            // Unnumbered, or tied: by filename, in natural order. Loose files
            // filed as Specials often all carry the show's name — twenty-seven
            // called "Bright Mornings" — so the title told them apart in no order at
            // all; the filenames, numbered by whoever made them, do.
            default:
                let left = a.item.path.map { ($0 as NSString).lastPathComponent } ?? a.item.name
                let right = b.item.path.map { ($0 as NSString).lastPathComponent } ?? b.item.name
                return left == right ? finder(a.item.name, b.item.name) : finder(left, right)
            }
        }
    }
}

public extension LibraryEntry {

    /// Whether this season is the specials bag rather than a season of the show.
    ///
    /// Jellyfin models specials as "Season 0", which puts OVAs, recaps, picture
    /// dramas and creditless openings in the picker as a peer of Season 1. They
    /// are not a season: nothing in them continues anything, and a viewer
    /// choosing what to watch next is never choosing between "Season 2" and
    /// "the bag of extras".
    var isSpecialsSeason: Bool {
        item.itemType == .season && item.indexNumber == 0
    }

    /// What a season is called in the picker.
    ///
    /// "Extras" rather than "Specials" or "Season 0": it is what the strip
    /// actually holds, and it is the word that stops it reading as a numbered
    /// season with an unusual name.
    var seasonPickerName: String {
        isSpecialsSeason ? "Extras" : item.name
    }
}
