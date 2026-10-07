import Foundation
import TestKit
import LumiereKit

/// Deciding whether an identify landed, after the connection dropped mid-scrape.
///
/// The stakes are asymmetric and both directions are bad: too strict and a working
/// identify is reported as "the network connection was lost" — the complaint this
/// came from — too loose and a failure is reported as success.
@MainActor
func registerProviderIdMatchTests(_ t: TestRunner) {
    t.suite("Provider id match") { t in

        t.test("a match is found whatever the casing") {
            // Real shape: a search result says TMDB, Jellyfin stores Tmdb.
            t.expect(ProviderIdMatch.matches(
                expected: ["TMDB": "1429"],
                actual: ["Tmdb": "1429", "Tvdb": "79895"]
            ))
        }

        t.test("hex ids differing only in case still match") {
            t.expect(ProviderIdMatch.matches(
                expected: ["AniList": "ABC123"],
                actual: ["anilist": "abc123"]
            ))
        }

        t.test("one id matching is enough") {
            // The server may have found the title on one provider and not another;
            // requiring all of them would call a good identify a failure.
            t.expect(ProviderIdMatch.matches(
                expected: ["Tmdb": "1429", "Tvdb": "79895"],
                actual: ["Tmdb": "1429"]
            ))
        }

        t.test("a different id is not a match") {
            t.expect(!ProviderIdMatch.matches(
                expected: ["Tmdb": "1429"],
                actual: ["Tmdb": "9999"]
            ))
        }

        t.test("the same value under another provider is not a match") {
            // Ids are only meaningful next to their provider — 1429 on TMDB and
            // 1429 on TVDB are different shows.
            t.expect(!ProviderIdMatch.matches(
                expected: ["Tmdb": "1429"],
                actual: ["Tvdb": "1429"]
            ))
        }

        t.test("nothing to compare is never a match") {
            t.expect(!ProviderIdMatch.matches(expected: [:], actual: ["Tmdb": "1429"]))
            t.expect(!ProviderIdMatch.matches(expected: ["Tmdb": "1429"], actual: [:]))
        }

        t.test("ids are read out of a raw payload, ignoring non-strings") {
            // Jellyfin returns nulls for providers it has no id from.
            let object: [String: Any] = [
                "Name": "Attack on Titan",
                "ProviderIds": ["Tmdb": "1429", "Tvdb": NSNull(), "Imdb": "tt2560140"],
            ]
            let ids = ProviderIdMatch.providerIds(in: object)
            t.expectEqual(ids.count, 2)
            t.expectEqual(ids["Tmdb"], "1429")
            t.expectNil(ids["Tvdb"])
        }

        t.test("a payload with no ids at all yields nothing") {
            t.expectEqual(ProviderIdMatch.providerIds(in: ["Name": "X"]).count, 0)
        }
    }
}
