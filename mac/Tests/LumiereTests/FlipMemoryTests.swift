import Foundation
import TestKit
import LumiereKit

@MainActor
func registerFlipMemoryTests(_ t: TestRunner) {
    t.suite("Flip memory") { t in
        t.test("a show keeps its flip; another show is untouched") {
            let defaults = UserDefaults(suiteName: "lumiere.tests.flip")!
            defaults.removePersistentDomain(forName: "lumiere.tests.flip")
            FlipMemory.remember(horizontal: true, vertical: false, for: "show", in: defaults)
            let kept = FlipMemory.flip(for: "show", in: defaults)
            t.expect(kept.horizontal && !kept.vertical)
            let other = FlipMemory.flip(for: "film", in: defaults)
            t.expect(!other.horizontal && !other.vertical)
        }

        t.test("unflipping forgets rather than storing a zero") {
            let defaults = UserDefaults(suiteName: "lumiere.tests.flip2")!
            defaults.removePersistentDomain(forName: "lumiere.tests.flip2")
            FlipMemory.remember(horizontal: true, vertical: true, for: "show", in: defaults)
            FlipMemory.remember(horizontal: false, vertical: false, for: "show", in: defaults)
            t.expect(defaults.dictionary(forKey: FlipMemory.storageKey)?["show"] == nil)
        }
    }
}
