import Foundation
import TestKit
import LumiereKit

/// Seeding Identify from the folder rather than from the scrape that is wrong.
///
/// Every path below is a real shape from this library — the same ones
/// `FilenameEpisodeRepair` and `FilenameFranchise` were written against — because
/// the only thing that makes a cleaning rule right is the folder it was learned
/// from.
@MainActor
func registerPathTitleGuessTests(_ t: TestRunner) {

    func guess(_ path: String, isFolder: Bool = false) -> String? {
        PathTitleGuess.title(path: path, isFolder: isFolder)
    }

    t.suite("Path title guess") { t in

        t.test("a film takes the folder above it, not the filename") {
            t.expectEqual(
                guess("/Volumes/Media/Movies/Blade Runner 2049/Blade Runner 2049.mkv"),
                "Blade Runner 2049"
            )
        }

        t.test("a year in brackets after the name is dropped") {
            // The `arcName` shape: Jellyfin's own recommended folder layout.
            t.expectEqual(
                guess("/Volumes/Media/Anime/Nisemonogatari (2012)/"
                    + "Nisemonogatari - 1x11 - Tsukihi Phoenix, Part 4.mkv"),
                "Nisemonogatari"
            )
        }

        t.test("a year range is dropped too") {
            t.expectEqual(
                guess("/Volumes/Media/Movies/Star Trek Complete Set (1979-2016)/"
                    + "Star Trek II.mkv"),
                "Star Trek Complete Set"
            )
        }

        t.test("parentheses that are not a year are kept") {
            // "Rinne no Lagrange (The Flower of Rin-ne)" is the folder's real name
            // and both halves are searchable; only a year is noise to a provider.
            t.expectEqual(
                guess("/Volumes/Media/Anime/Rinne no Lagrange (The Flower of Rin-ne)/"
                    + "Rinne no Lagrange - 1x01.mkv"),
                "Rinne no Lagrange (The Flower of Rin-ne)"
            )
        }

        t.test("a season folder is stepped over") {
            t.expectEqual(
                guess("/Volumes/Media/TV Shows/FBI (2018)/Season 4/"
                    + "FBI - 4x01 - Never Trust a Stranger.mkv"),
                "FBI"
            )
        }

        t.test("an extras folder is stepped over") {
            // The real `[Judas]` extras folder. Both the folder and the bracketed
            // group have to go, or the seed reads "Extras".
            t.expectEqual(
                guess("/Volumes/Media/Anime/Sky Wizards Academy/Extras/"
                    + "[Judas] NCOP #01.mkv"),
                "Sky Wizards Academy"
            )
        }

        t.test("a series is its own folder") {
            t.expectEqual(
                guess("/Volumes/Media/Anime/Hataraku Maou-sama!", isFolder: true),
                "Hataraku Maou-sama!"
            )
        }

        t.test("a season row walks up to the show") {
            t.expectEqual(
                guess("/Volumes/Media/Anime/Hataraku Maou-sama!/Season 2",
                      isFolder: true),
                "Hataraku Maou-sama!"
            )
        }

        t.test("a bracketed note on a folder is dropped with the dash it left") {
            // The folder that produced this feedback: the scrape called it
            // "Detective Conan" and the note is not part of any title.
            t.expectEqual(
                guess("/Volumes/Media/Anime/Detective Conan - [Rewatch Guide]",
                      isFolder: true),
                "Detective Conan"
            )
        }

        t.test("a fansub group leading a folder name is dropped") {
            t.expectEqual(
                guess("/Volumes/Media/Anime/[Judas] Rinne no Lagrange/"
                    + "[Judas] Rinne no Lagrange - NCED03.mkv"),
                "Rinne no Lagrange"
            )
        }

        t.test("a dash in the middle of a real title survives") {
            t.expectEqual(
                guess("/Volumes/Media/Anime/Monogatari - Off & Monster Season (2024)/"
                    + "Monogatari - Off & Monster Season - 1x01 - Orokamonogatari.mkv"),
                "Monogatari - Off & Monster Season"
            )
        }

        t.test("a machine-written name with no spaces gets word breaks") {
            t.expectEqual(
                guess("/Volumes/Media/Movies/the_matrix_1999_1080p/video.mp4"),
                "the matrix 1999"
            )
        }

        t.test("release tags are dropped as whole words") {
            t.expectEqual(
                guess("/Volumes/Media/Movies/Dune Part Two 2160p HEVC/Dune.mkv"),
                "Dune Part Two"
            )
        }

        t.test("a title that merely contains a tag word is untouched") {
            // "Complete" and "Collection" are in real folder names here, so they
            // are deliberately not in the tag list.
            t.expectEqual(
                guess("/Volumes/Media/Anime Movies/Lupin III - Movie Collection (1969-2019)",
                      isFolder: true),
                "Lupin III - Movie Collection"
            )
        }

        t.test("the walk-up never reaches the volume") {
            // Nothing above the disk name is anybody's title, however structural
            // the folder below it looks. The disk name survives as an initialism
            // rather than being broken into letters — the trailing dot goes with
            // the dangling-separator trim, which is what it is there for.
            t.expectEqual(guess("/Volumes/Media/Extras/thing.mkv"), "Media")
        }

        t.test("no path falls back to the name the caller had") {
            t.expectEqual(
                PathTitleGuess.query(path: nil, isFolder: false, fallback: "Scraped Name"),
                "Scraped Name"
            )
            t.expectEqual(
                PathTitleGuess.query(path: "", isFolder: false, fallback: "Scraped Name"),
                "Scraped Name"
            )
        }

        t.test("a path that cleans to nothing falls back too") {
            t.expectEqual(
                PathTitleGuess.query(
                    path: "/Volumes/Media/[Judas]/thing.mkv",
                    isFolder: false, fallback: "Scraped Name"
                ),
                "Scraped Name"
            )
        }
    }
}
