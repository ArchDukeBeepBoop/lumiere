import Foundation
import TestKit
import LumiereKit

/// The two decisions offline mode is built on, both pure and both easy to get
/// subtly wrong in ways nothing would notice for months.
///
/// `isUnreachable` is the one that decides whether the app goes offline at all. Get
/// it too eager and a 401 puts the whole app into offline mode with a reconnect
/// probe that succeeds immediately, syncs, fails the same way, and goes round again
/// — a loop, just a polite one. Get it too shy and a server that is genuinely gone
/// produces a network error per screen, which is exactly what this feature exists
/// to replace.
///
/// `retryDelay` is the one that decides how often an absent server is asked. This
/// project has already shipped an unbounded retry loop once (see the
/// consecutive-failure comment in `LibraryRepository+Sync`), so the backoff is
/// pinned here rather than trusted.
@MainActor
func registerOfflineModeTests(_ t: TestRunner) {

    t.suite("Offline detection") { t in

        t.test("a transport failure is an outage") {
            t.expect(ConnectionState.isUnreachable(
                JellyfinError.notReachable(underlying: "Connection refused")
            ))
        }

        t.test("a server that answers is not an outage") {
            // All three of these mean the server is up. Going offline for any of
            // them would start a probe that resolves on its first attempt and
            // changes nothing except how often the same failure recurs.
            t.expect(!ConnectionState.isUnreachable(JellyfinError.unauthorized))
            t.expect(!ConnectionState.isUnreachable(
                JellyfinError.httpError(status: 500, body: "Internal Server Error")
            ))
            t.expect(!ConnectionState.isUnreachable(
                JellyfinError.decodingFailed(context: "items", underlying: "bad JSON")
            ))
        }

        t.test("cancellation is never an outage") {
            // The Stop button, a folder change discarding a page in flight, sign-out.
            // Treating any of them as a downed server would put an outage banner
            // over a sync the user stopped on purpose.
            t.expect(!ConnectionState.isUnreachable(CancellationError()))
        }

        t.test("raw URL errors are classified too") {
            // Not everything reaches the connection state through
            // `JellyfinClient.execute`, which folds URLSession failures into
            // `notReachable`. Downloads and artwork have their own sessions.
            for code: URLError.Code in [
                .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
                .networkConnectionLost, .timedOut, .dnsLookupFailed,
            ] {
                t.expect(
                    ConnectionState.isUnreachable(URLError(code)),
                    "\(code) should read as unreachable"
                )
            }
        }

        t.test("an NSError from URLSession is classified like a URLError") {
            // What a bridged error looks like once it has been through an
            // `as NSError` cast somewhere in the chain.
            let bridged = NSError(
                domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost
            )
            t.expect(ConnectionState.isUnreachable(bridged))
        }

        t.test("a rejected certificate is not treated as a transient outage") {
            // It is a configuration problem. Retrying it every minute forever would
            // never fix it, and the banner would say "trying again" about something
            // that cannot succeed.
            t.expect(!ConnectionState.isUnreachable(URLError(.secureConnectionFailed)))
        }

        t.test("an error unrelated to the network is left alone") {
            t.expect(!ConnectionState.isUnreachable(
                NSError(domain: "SQLite", code: 11)
            ))
        }
    }

    t.suite("Reconnect backoff") { t in

        t.test("the first attempt is soon but not immediate") {
            let first = ConnectionState.retryDelay(attempt: 0)
            t.expect(first >= 5, "too tight: \(first)s between probes")
            t.expect(first <= 10, "too slow to notice a server restarting: \(first)s")
        }

        t.test("it widens with every failure") {
            var previous = ConnectionState.retryDelay(attempt: 0)
            for attempt in 1...4 {
                let delay = ConnectionState.retryDelay(attempt: attempt)
                t.expect(delay > previous, "attempt \(attempt) did not back off")
                previous = delay
            }
        }

        t.test("it stops widening at two minutes") {
            // The ceiling matters as much as the growth: without one, a Mac left
            // asleep for a day would come back with an hours-long interval and the
            // server would look unreachable long after it was not.
            t.expectEqual(ConnectionState.retryDelay(attempt: 40), 120)
            t.expectEqual(ConnectionState.retryDelay(attempt: 5), 120)
        }

        t.test("an absurd attempt count does not overflow into a silent stall") {
            // `5 * 2^n` overflows Double's useful range long before Int's, and an
            // infinite or NaN delay is a sleep that never returns — a probe that
            // has stopped without anything saying so.
            let delay = ConnectionState.retryDelay(attempt: 10_000)
            t.expect(delay.isFinite, "non-finite delay")
            t.expectEqual(delay, 120)
        }

        t.test("a day offline costs a bounded number of requests") {
            // The whole point of the backoff, stated as the thing that actually
            // matters. At the ceiling this is one request every two minutes.
            var elapsed: TimeInterval = 0
            var probes = 0
            while elapsed < 24 * 60 * 60 {
                elapsed += ConnectionState.retryDelay(attempt: probes)
                probes += 1
            }
            t.expect(probes < 800, "\(probes) probes a day is too many")
        }
    }
}
