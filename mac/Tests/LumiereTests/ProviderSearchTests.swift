import Foundation
import TestKit
import LumiereKit

/// Provider search, and the parts that are logic rather than network.
@MainActor
func registerProviderSearchTests(_ t: TestRunner) async {

    await t.suite("Metadata providers") { t in

        t.test("each provider maps to the id key Jellyfin expects") {
            // Getting this wrong means the server accepts the request and scrapes
            // nothing, which looks like the feature silently not working.
            let tmdb = ProviderMatch(
                provider: .tmdb, providerId: "1", title: "A",
                originalTitle: nil, year: nil, overview: nil, posterURL: nil
            )
            t.expectEqual(tmdb.jellyfinProviderKey, "Tmdb")

            let tvdb = ProviderMatch(
                provider: .tvdb, providerId: "2", title: "B",
                originalTitle: nil, year: nil, overview: nil, posterURL: nil
            )
            t.expectEqual(tvdb.jellyfinProviderKey, "Tvdb")
        }

        t.test("a match is identified by provider and id together") {
            // The same numeric id means different things at TMDB and TheTVDB, so the
            // id alone cannot be the identity.
            let a = ProviderMatch(
                provider: .tmdb, providerId: "42", title: "A",
                originalTitle: nil, year: nil, overview: nil, posterURL: nil
            )
            let b = ProviderMatch(
                provider: .tvdb, providerId: "42", title: "A",
                originalTitle: nil, year: nil, overview: nil, posterURL: nil
            )
            t.expect(a.id != b.id, "ids collided across providers: \(a.id)")
        }

        t.test("a blank or short date yields no year rather than a wrong one") {
            // TMDB sends "" for unknown dates, and a DateFormatter would invent a year.
            t.expect(ProviderSearch.year(from: "") == nil)
            t.expect(ProviderSearch.year(from: nil) == nil)
            t.expect(ProviderSearch.year(from: "20") == nil)
            t.expectEqual(ProviderSearch.year(from: "2022-04-09"), 2022)
        }

        await t.test("searching without a key says so, rather than returning nothing") {
            // "No matches" and "you have not added a key" need different responses
            // from the user.
            do {
                _ = try await ProviderSearch.search(.tvdb, query: "x", isSeries: true)
                t.expect(false, "expected an error")
            } catch let error as ProviderSearch.SearchError {
                let message = error.errorDescription ?? ""
                t.expect(
                    message.contains("key") || message.contains("not implemented"),
                    "unhelpful message: \(message)"
                )
            }
        }

        t.test("every provider names one host, so egress stays auditable") {
            for provider in MetadataProvider.allCases {
                t.expect(!provider.host.isEmpty, "\(provider) has no host")
                t.expect(!provider.host.contains("/"), "\(provider) host is a URL, not a host")
            }
        }
    }
}
