import Foundation
import TestKit
import LumiereKit

/// The offline banner is only as good as the sentence in it.
///
/// These exist because the failure path had no observable behaviour at all before
/// this phase: a sync error set a string that nothing rendered, so a server that
/// was down looked identical to a server with nothing new. Pinning the message
/// mapping keeps the distinction that makes the banner actionable — "unauthorised"
/// and "connection refused" need different responses from the user.
@MainActor
func registerConnectionStateTests(_ t: TestRunner) {

    t.suite("Connection state") { t in

        t.test("a Jellyfin error uses its own wording, not the generic one") {
            let message = ConnectionState.message(
                for: JellyfinError.notReachable(underlying: "Connection refused")
            )
            t.expect(
                message.contains("Couldn't reach the server"),
                "expected the Jellyfin wording, got \(message)"
            )
            t.expect(message.contains("Connection refused"), "lost the underlying cause")
        }

        t.test("an unauthorised server is not reported as unreachable") {
            // These call for different actions — one is "start the server", the
            // other is "sign in again" — so collapsing them would be a real loss.
            let unauthorized = ConnectionState.message(for: JellyfinError.unauthorized)
            let unreachable = ConnectionState.message(
                for: JellyfinError.notReachable(underlying: "timed out")
            )
            t.expect(unauthorized != unreachable, "both errors produced the same message")
            t.expect(!unauthorized.contains("reach"), "unauthorised read as unreachable")
        }

        t.test("a non-Jellyfin error still produces something to show") {
            let error = NSError(
                domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
            )
            let message = ConnectionState.message(for: error)
            t.expectEqual(message, "The request timed out.")
        }

        t.test("an HTTP failure carries the status through") {
            let message = ConnectionState.message(
                for: JellyfinError.httpError(status: 502, body: "Bad Gateway")
            )
            t.expect(message.contains("502"), "status code lost: \(message)")
        }

        t.test("only offline reports itself as offline") {
            t.expect(ConnectionState.offline("down").isOffline)
            t.expect(!ConnectionState.online.isOffline)
            t.expect(!ConnectionState.unknown.isOffline)
        }

        t.test("a reconnect is distinguishable from never having tried") {
            // The shell shows the empty-cache offline state on `.offline` only, so
            // `.unknown` during a retry must not be mistaken for a failure.
            t.expect(ConnectionState.unknown != ConnectionState.offline("down"))
            t.expect(ConnectionState.online != ConnectionState.unknown)
        }
    }
}
