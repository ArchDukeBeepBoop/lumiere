import Foundation

/// Which libraries each Top 10 row ranks.
///
/// `LibraryKinds` guesses from the library's name and collection type, and on a real
/// server that guess runs out. This one has four `tvshows` libraries — television,
/// anime, a Hobby channel and an adult library — and nothing in Jellyfin's data
/// separates the first from the last: the collection type is identical, the names
/// share no pattern, and the age ratings are a scatter of "M", "18+", "NC16" and
/// nothing at all across every one of them. The row filled with titles rated a clean
/// 10.0 by a handful of people and television vanished from its own chart.
///
/// It briefly worked by leaning on the private-library setting, which was worse than
/// no rule: privacy is a statement about what is on screen right now, and when that
/// setting was cleared the charts silently changed. A ranking should not depend on a
/// preference about visibility.
///
/// So the owner says. The guess stays as the default, because it is right on a
/// straightforward server and nobody should have to configure anything to get a
/// sensible row — but the moment a choice is stored it wins, and it keeps winning.
public enum TopShelfSelection {

    private static func key(_ kind: LibraryKinds.Kind) -> String {
        "top10Libraries.\(kind.rawValue)"
    }

    /// The stored choice, or nil where none has been made.
    ///
    /// Nil and empty are deliberately different. Nil means "never chosen, infer it";
    /// empty means "chosen, and the answer is none of them" — which has to be
    /// respected, or unticking the last library would silently restore the guess.
    public static func stored(for kind: LibraryKinds.Kind) -> Set<String>? {
        guard let raw = UserDefaults.standard.string(forKey: key(kind)) else { return nil }
        return Set(raw.split(separator: ",").map(String.init))
    }

    public static func store(_ ids: Set<String>, for kind: LibraryKinds.Kind) {
        UserDefaults.standard.set(ids.sorted().joined(separator: ","), forKey: key(kind))
    }

    /// Clears the choice, so the row goes back to being inferred.
    public static func clear(_ kind: LibraryKinds.Kind) {
        UserDefaults.standard.removeObject(forKey: key(kind))
    }

    public static func isChosen(_ kind: LibraryKinds.Kind) -> Bool {
        stored(for: kind) != nil
    }

    /// What the row should actually query.
    ///
    /// A stored choice is filtered against the libraries that still exist, so a
    /// library removed from the server does not leave a dead id in the query — and
    /// it is *not* filtered against `excluded`, because ticking a library by hand is
    /// a more specific instruction than any default about privacy.
    public static func libraryIds(
        for kind: LibraryKinds.Kind,
        in libraries: [LibraryRecord],
        excluding excluded: Set<String>
    ) -> [String] {
        guard let chosen = stored(for: kind) else {
            return LibraryKinds.libraryIds(for: kind, in: libraries, excluding: excluded)
        }
        return libraries.map(\.id).filter { chosen.contains($0) }
    }

    /// The libraries worth offering for a row.
    ///
    /// Every library Jellyfin has classified as film or television, whatever the
    /// name suggests — the whole point is that the owner may disagree with the guess,
    /// so the list must include what the guess left out. Music, playlists,
    /// collections and folder libraries are absent because they carry no community
    /// ratings to rank by.
    public static func candidates(in libraries: [LibraryRecord]) -> [LibraryRecord] {
        libraries.filter {
            $0.collectionType == "movies" || $0.collectionType == "tvshows"
        }
    }
}
