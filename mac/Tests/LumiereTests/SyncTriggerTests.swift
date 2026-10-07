import Foundation
import TestKit
import LumiereKit

/// When a server-side repair forces a full read.
@MainActor
func registerSyncTriggerTests(_ t: TestRunner) {

    t.suite("Sync trigger") { t in

        t.test("a repair after the last full read forces one") {
            let lastFull = Date(timeIntervalSince1970: 1_000_000)
            t.expect(SyncTrigger.repairedSince(lastFull: lastFull, repairedAt: "1970-01-12T14:46:41Z"))
        }

        t.test("a repair before it does not") {
            let lastFull = Date(timeIntervalSince1970: 1_000_000)
            t.expect(!SyncTrigger.repairedSince(lastFull: lastFull, repairedAt: "1970-01-12T13:46:39Z"))
        }

        t.test("a server that does not say never forces one") {
            t.expect(!SyncTrigger.repairedSince(lastFull: nil, repairedAt: nil))
            t.expect(!SyncTrigger.repairedSince(lastFull: nil, repairedAt: "not a date"))
        }

        t.test("no full read yet plus a repair stamp reads everything") {
            t.expect(SyncTrigger.repairedSince(lastFull: nil, repairedAt: "2026-09-16T10:00:00Z"))
        }
    }
}
