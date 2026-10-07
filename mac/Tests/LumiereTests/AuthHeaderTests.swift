import Foundation
import TestKit
import LumiereKit

/// The header that made signing in impossible.
///
/// macOS names a Mac "Jeremiah’s MacBook Pro" with a curly apostrophe (U+2019), and
/// that went into the `Authorization` header unaltered. URLSession sends non-ASCII
/// in a form ASP.NET Core refuses to parse, so Jellyfin returned 400 *before*
/// checking credentials — no password could ever have worked, and the UI reported it
/// as a server error rather than anything actionable.
///
/// `curl` sends the same bytes and gets a normal 401, so this was invisible to
/// command-line testing. That is exactly why it needs a test.
@MainActor
func registerAuthHeaderTests(_ t: TestRunner) {

    t.suite("Authorization header") { t in

        t.test("a curly apostrophe becomes a plain one rather than breaking the header") {
            let safe = JellyfinClient.headerSafeValue("Jeremiah’s MacBook Pro")
            t.expectEqual(safe, "Jeremiah's MacBook Pro")
            t.expect(safe.allSatisfy(\.isASCII), "non-ASCII survived: \(safe)")
        }

        t.test("every character in the built header is ASCII") {
            // The invariant that actually matters. Whatever the machine is called,
            // the header must be transmittable.
            let header = JellyfinClient.headerSafeValue("Ünïcodé — Mäc “Pro”")
            t.expect(header.allSatisfy(\.isASCII), "non-ASCII survived: \(header)")
        }

        t.test("quotes and commas are removed, since the scheme delimits on them") {
            // A Mac named this would otherwise split one parameter into several and
            // corrupt every field after it.
            let safe = JellyfinClient.headerSafeValue("My \"Media\" Box, v2")
            t.expect(!safe.contains("\""), "quote survived: \(safe)")
            t.expect(!safe.contains(","), "comma survived: \(safe)")
        }

        t.test("control characters cannot smuggle in a header break") {
            let safe = JellyfinClient.headerSafeValue("Mac\r\nX-Injected: 1")
            t.expect(!safe.contains("\r") && !safe.contains("\n"), "newline survived: \(safe)")
        }

        t.test("a name that sanitizes to nothing still yields a usable device name") {
            // An empty quoted parameter is not obviously valid, and a blank device
            // in the server's list is worse than a generic one.
            t.expectEqual(JellyfinClient.headerSafeValue("’’’"), "'''")
            t.expectEqual(JellyfinClient.headerSafeValue("\u{201C}\u{201D}"), "Mac")
            t.expectEqual(JellyfinClient.headerSafeValue(""), "Mac")
        }

        t.test("runs of whitespace collapse instead of leaving gaps") {
            t.expectEqual(JellyfinClient.headerSafeValue("Mac   Mini"), "Mac Mini")
        }

        t.test("an ordinary ASCII name is left exactly as it is") {
            t.expectEqual(JellyfinClient.headerSafeValue("Mac Studio"), "Mac Studio")
        }
    }
}
