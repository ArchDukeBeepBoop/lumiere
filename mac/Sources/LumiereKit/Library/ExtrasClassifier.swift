import Foundation

/// Recognises bonus content by the folder it sits in.
///
/// Jellyfin only sets `ExtraType` when *it* recognises something as an extra, and on
/// a real library it frequently does not: four Ghost in the Shell featurettes sitting
/// in a `Bonus/` folder came back as ordinary `Movie` items with no ExtraType at all,
/// so they filled the Anime Movies grid alongside the actual films. Every row in a
/// 44,000-item cache had a null ExtraType, so there was nothing to filter on.
///
/// The folder name is the signal that actually survives. Naming bonus material into a
/// subfolder is the shared convention behind Jellyfin, Plex and Kodi's own scanners,
/// so matching that list catches what the server missed without guessing at content.
///
/// Pure and path-only, so it is testable without a server or a database — the project
/// keeps its classification logic that way deliberately.
public enum ExtrasClassifier {

    /// Folder names that mean "this is bonus material, not a title in its own right".
    ///
    /// Deliberately narrower than the list Jellyfin, Plex and Kodi scan for, because
    /// several of theirs are ambiguous enough to hide real content. Checking the
    /// candidate list against a real 44,000-item library caught exactly that:
    ///
    /// - `specials` matched 531 rows, and 519 of them were **Episodes** — anime
    ///   specials and OVAs, which are content someone means to watch, not bonus
    ///   material. Twelve were even in ordinary numbered seasons. Jellyfin already
    ///   models these properly as season 0, so nothing here needs to touch them.
    /// - `shorts`, `scenes`, `other` and `misc` are generic enough to be somebody's
    ///   real folder of real films. They matched nothing in that library, so
    ///   including them bought no accuracy and risked hiding titles.
    ///
    /// What is left is unambiguous: a file under one of these is about a film rather
    /// than being one.
    static let extraFolderNames: Set<String> = [
        "extras", "extra", "bonus", "bonus disc", "bonusdisc",
        "featurettes", "featurette",
        "behind the scenes", "behindthescenes",
        "deleted scenes", "deletedscenes",
        "interviews", "interview",
        "trailers", "trailer",
        "samples", "sample",
        "special features", "specialfeatures",
        "making of", "makingof",
    ]

    /// Whether a file's path puts it inside a bonus folder.
    ///
    /// Only the *directory* components are examined, never the filename: a film
    /// genuinely called "Trailer Park Boys" must not be classified as a trailer
    /// because of its own name.
    public static func isExtra(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }

        let components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        // Drop the last component: that is the file itself.
        guard components.count > 1 else { return false }

        return components.dropLast().contains { component in
            extraFolderNames.contains(
                component.lowercased().trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
