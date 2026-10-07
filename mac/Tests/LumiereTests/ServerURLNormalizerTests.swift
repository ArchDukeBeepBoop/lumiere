import TestKit
import LumiereKit

@MainActor
func registerServerURLNormalizerTests(_ t: TestRunner) {
    t.suite("Server URL normalizer") { t in

        func strings(_ input: String) -> [String] {
            ServerURLNormalizer.candidates(from: input).map(\.absoluteString)
        }

        t.test("bare IP tries http then the default port then https") {
            t.expectEqual(
                strings("192.168.60.40"),
                ["http://192.168.60.40", "http://192.168.60.40:8096", "https://192.168.60.40"]
            )
        }

        t.test("explicit port is respected and not duplicated") {
            t.expectEqual(
                strings("192.168.60.40:8920"),
                ["http://192.168.60.40:8920", "https://192.168.60.40:8920"]
            )
        }

        t.test("explicit scheme is not second-guessed") {
            t.expectEqual(strings("https://media.example.com"), ["https://media.example.com"])
        }

        t.test("mDNS hostname works") {
            t.expectEqual(
                strings("jellyfin.local:8096"),
                ["http://jellyfin.local:8096", "https://jellyfin.local:8096"]
            )
        }

        t.test("a pasted web UI URL is reduced to the API root") {
            t.expectEqual(
                strings("http://192.168.60.40:8096/web/index.html#!/home.html"),
                ["http://192.168.60.40:8096"]
            )
        }

        t.test("trailing slash is stripped") {
            t.expectEqual(strings("https://media.example.com/"), ["https://media.example.com"])
        }

        t.test("a subpath behind a reverse proxy is stripped too") {
            // Losing the subpath is the right call: /System/Info/Public would 404
            // under it anyway, and the user can re-enter the full base if needed.
            t.expectEqual(strings("https://example.com/jellyfin"), ["https://example.com"])
        }

        t.test("whitespace is tolerated") {
            t.expectEqual(strings("  192.168.60.40:8096  "),
                          ["http://192.168.60.40:8096", "https://192.168.60.40:8096"])
        }

        t.test("query strings are dropped") {
            t.expectEqual(strings("http://box:8096?foo=bar"), ["http://box:8096"])
        }

        t.test("empty and junk input yields nothing") {
            t.expect(strings("").isEmpty)
            t.expect(strings("   ").isEmpty)
            t.expect(strings("://").isEmpty)
            t.expect(strings(":8096").isEmpty)
            t.expect(strings("http://").isEmpty)
        }

        t.test("a non-numeric port is rejected rather than probed") {
            t.expect(strings("192.168.60.40:abcd").isEmpty)
            t.expect(strings("192.168.60.40:").isEmpty)
        }

        t.test("an out-of-range port is rejected") {
            t.expect(strings("192.168.60.40:99999").isEmpty)
            t.expect(strings("192.168.60.40:0").isEmpty)
        }

        t.test("IPv6 literal keeps its colons and is not mistaken for a port") {
            t.expectEqual(
                strings("[fe80::1]:8096"),
                ["http://[fe80::1]:8096", "https://[fe80::1]:8096"]
            )
        }

        t.test("IPv6 literal without a port still gets the default port candidate") {
            t.expectEqual(
                strings("[fe80::1]"),
                ["http://[fe80::1]", "http://[fe80::1]:8096", "https://[fe80::1]"]
            )
        }
    }
}
