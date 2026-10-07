import Foundation
import TestKit
import LumiereKit

/// Which files count as bonus material, decided from the path alone.
@MainActor
func registerExtrasClassifierTests(_ t: TestRunner) {

    t.suite("Extras classifier") { t in

        t.test("a file in a Bonus folder is an extra") {
            // The case that exposed this: Jellyfin returned these as ordinary Movie
            // items with no ExtraType, so they stood in the grid beside the films.
            t.expect(ExtrasClassifier.isExtra(
                path: "/Volumes/Media/Anime Movies/Ghost in the Shell/Bonus/01 Production Report.mkv"
            ))
        }

        t.test("the films beside it are not") {
            t.expect(!ExtrasClassifier.isExtra(
                path: "/Volumes/Media/Anime Movies/Ghost in the Shell/Ghost in the Shell - The Movie (1995).mkv"
            ))
        }

        t.test("Specials is deliberately not an extras folder") {
            // 519 anime specials and OVAs live in Specials/ and are content someone
            // means to watch. Jellyfin already models them as season 0; classifying
            // them here would hide them from their own episode lists.
            t.expect(!ExtrasClassifier.isExtra(
                path: "/Volumes/Media/Anime/My-HiME/Specials/My-HiME - Special 24.mkv"
            ))
        }

        t.test("a folder generic enough to hold real films is not an extras folder") {
            // "Other", "Misc" and "Shorts" are all plausible names for a real
            // collection, so they are left alone rather than risking hidden titles.
            t.expect(!ExtrasClassifier.isExtra(path: "/media/Movies/Other/Real Film.mkv"))
            t.expect(!ExtrasClassifier.isExtra(path: "/media/Movies/Shorts/Real Short.mkv"))
        }

        t.test("the filename alone never classifies") {
            // Otherwise a film genuinely called this would be filed as a trailer.
            t.expect(!ExtrasClassifier.isExtra(path: "/media/Movies/Trailer Park Boys (1999).mkv"))
            t.expect(!ExtrasClassifier.isExtra(path: "/media/Movies/Bonus.mkv"))
        }

        t.test("matching is case-insensitive and ignores stray spacing") {
            t.expect(ExtrasClassifier.isExtra(path: "/media/Film/EXTRAS/clip.mkv"))
            t.expect(ExtrasClassifier.isExtra(path: "/media/Film/Behind The Scenes/clip.mkv"))
        }

        t.test("a bare filename with no folder is never an extra") {
            t.expect(!ExtrasClassifier.isExtra(path: "movie.mkv"))
            t.expect(!ExtrasClassifier.isExtra(path: ""))
            t.expect(!ExtrasClassifier.isExtra(path: nil))
        }

        t.test("only whole path components match, not substrings of them") {
            // "Extraordinary" contains "extra" but is not an extras folder.
            t.expect(!ExtrasClassifier.isExtra(path: "/media/Movies/Extraordinary Films/A Film.mkv"))
        }
    }
}
