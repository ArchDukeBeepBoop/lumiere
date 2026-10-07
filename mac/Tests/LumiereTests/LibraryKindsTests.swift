import Foundation
import TestKit
import LumiereKit

/// Which libraries each Top 10 row draws from.
///
/// Pinned because it is a guess made from folder names — the only place the anime
/// distinction exists, since Jellyfin gives an anime library the same
/// `collectionType` as a live-action one. A guess with no test is a guess that
/// changes silently.
@MainActor
func registerLibraryKindsTests(_ t: TestRunner) async {

    // The real shape of this server's libraries, so the test fails if the rule
    // stops sorting them the way the rows expect.
    let libraries: [(id: String, name: String, collectionType: String?)] = [
        ("anime", "Anime", "tvshows"),
        ("animeMovies", "Anime Movies", "movies"),
        ("movies", "Movies", "movies"),
        ("tv", "TV Shows", "tvshows"),
        ("hobby", "Hobby TV", "tvshows"),
        // Marked private on this server. `tvshows`, and its name says nothing about
        // anime, so nothing but an explicit exclusion keeps it out of the series row.
        ("adult", "Adult", "tvshows"),
        ("collections", "Collections", "boxsets"),
        ("threeD", "3D", nil),
        ("myVideos", "My Videos", nil),
        ("music", "Music", "music"),
        ("playlists", "Playlists", "playlists"),
    ]

    t.suite("Library kinds") { t in

        t.test("films are films, and not anime films") {
            let ids = LibraryKinds.libraryIds(for: .films, in: libraries)
            t.expectEqual(ids, ["movies"])
        }

        t.test("series are television, and not anime") {
            // Hobby TV is television. It is not anime, and it has no row of its
            // own, so it belongs here.
            let ids = LibraryKinds.libraryIds(
                for: .series, in: libraries, excluding: ["adult"]
            )
            t.expectEqual(ids, ["tv", "hobby"])
        }

        t.test("a private library is out of the charts even when it is on screen") {
            // The bug this pins: the row leaned on the ordinary privacy filter, which
            // is a statement about *right now*, so revealing the library moved it
            // into the charts. Twelve titles rated a clean 10.0 by a handful of
            // people then pushed television out of its own row.
            let revealed = LibraryKinds.libraryIds(for: .series, in: libraries)
            t.expect(revealed.contains("adult"),
                     "without an exclusion it is just another tvshows library")

            let excluded = LibraryKinds.libraryIds(
                for: .series, in: libraries, excluding: ["adult"]
            )
            t.expect(!excluded.contains("adult"))
        }

        t.test("anime takes both its libraries, films included") {
            let ids = LibraryKinds.libraryIds(for: .anime, in: libraries)
            t.expectEqual(ids, ["anime", "animeMovies"])
        }

        t.test("folder libraries are in no row at all") {
            // Nothing scraped them, so they carry no community rating — including
            // one would put unrated home video in a chart of the best films.
            let everything = LibraryKinds.libraryIds(for: .films, in: libraries)
                + LibraryKinds.libraryIds(for: .series, in: libraries)
                + LibraryKinds.libraryIds(for: .anime, in: libraries)
            t.expect(!everything.contains("threeD"))
            t.expect(!everything.contains("myVideos"))
        }

        t.test("music, playlists and collections are in no row either") {
            let everything = LibraryKinds.libraryIds(for: .films, in: libraries)
                + LibraryKinds.libraryIds(for: .series, in: libraries)
                + LibraryKinds.libraryIds(for: .anime, in: libraries)
            for id in ["music", "playlists", "collections"] {
                t.expect(!everything.contains(id), "\(id) should not be ranked")
            }
        }

        t.test("the anime match is case-insensitive and matches a substring") {
            t.expect(LibraryKinds.isAnime("Anime"))
            t.expect(LibraryKinds.isAnime("anime movies"))
            t.expect(LibraryKinds.isAnime("Old ANIME (Dubbed)"))
            t.expect(!LibraryKinds.isAnime("Animation"), "close, but a different word")
            t.expect(!LibraryKinds.isAnime("Movies"))
        }

        t.test("a server with no anime library still has films and series") {
            let plain: [(id: String, name: String, collectionType: String?)] = [
                ("m", "Movies", "movies"), ("t", "TV", "tvshows"),
            ]
            t.expectEqual(LibraryKinds.libraryIds(for: .films, in: plain), ["m"])
            t.expectEqual(LibraryKinds.libraryIds(for: .series, in: plain), ["t"])
            t.expect(LibraryKinds.libraryIds(for: .anime, in: plain).isEmpty,
                     "and no anime row, rather than one drawn from everything")
        }
    }
}
