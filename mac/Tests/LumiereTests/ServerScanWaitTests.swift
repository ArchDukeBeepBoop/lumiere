import Foundation
import TestKit
import LumiereKit

/// Knowing when the scan you asked for has finished.
@MainActor
func registerServerScanWaitTests(_ t: TestRunner) {

    // `LastFinished` is the scan's end time, which is what a waiter compares.
    func status(_ running: Bool, _ finished: String?) -> ServerScanStatus {
        ServerScanStatus(Running: running, Ended: finished)
    }

    t.suite("Waiting on a server scan") { t in

        t.test("a scan that has not started yet is not a scan that has finished") {
            // The whole reason this is not just `!Running`. Polled a moment
            // after asking, the server has not woken up: it says not running,
            // and its last finish time is from an hour ago. Treating that as
            // done syncs an unchanged library and calls it a success.
            let before = status(false, "2026-09-08T01:00:00Z")
            let now = status(false, "2026-09-08T01:00:00Z")
            t.expect(!ServerScanWait.isFinished(status: now, before: before, sawItRun: false))
        }

        t.test("still running is never finished") {
            let before = status(false, "2026-09-08T01:00:00Z")
            let now = status(true, "2026-09-08T01:00:00Z")
            t.expect(!ServerScanWait.isFinished(status: now, before: before, sawItRun: true))
        }

        t.test("watched it start, now stopped") {
            let before = status(false, "2026-09-08T01:00:00Z")
            let now = status(false, "2026-09-08T02:00:00Z")
            t.expect(ServerScanWait.isFinished(status: now, before: before, sawItRun: true))
        }

        t.test("a scan short enough to be missed between polls still counts") {
            // A small import can begin and end inside one second, so no poll
            // ever sees it running. The moved finish time is the only evidence,
            // and it is enough.
            let before = status(false, "2026-09-08T01:00:00Z")
            let now = status(false, "2026-09-08T01:00:05Z")
            t.expect(ServerScanWait.isFinished(status: now, before: before, sawItRun: false))
        }

        t.test("a server that has never scanned reports the first one honestly") {
            // No `LastFinished` at all beforehand — a server started minutes
            // ago. The first finish is a change from nothing to something.
            let before = status(false, nil)
            let now = status(false, "2026-09-08T01:00:00Z")
            t.expect(ServerScanWait.isFinished(status: now, before: before, sawItRun: false))
            // And before it finishes, still nothing.
            t.expect(!ServerScanWait.isFinished(status: before, before: before, sawItRun: false))
        }

        t.test("no reading beforehand does not block forever") {
            // The pre-read is best-effort; if it failed, a server reporting a
            // finish time at all is the best evidence available.
            let now = status(false, "2026-09-08T01:00:00Z")
            t.expect(ServerScanWait.isFinished(status: now, before: nil, sawItRun: false))
        }
    }
}
