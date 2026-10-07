import Foundation
import TestKit
import LumiereKit

/// Learning where a series' intro is from where someone skips.
@MainActor
func registerIntroLearningTests(_ t: TestRunner) {

    t.suite("Intro learning") { t in

        t.test("an ordinary seek is not an intro skip") {
            // Backwards, or from the middle of an episode, or too far to be an
            // opening — none of these are someone skipping a title sequence.
            t.expect(!IntroLearning.isIntroSkip(from: 400, to: 480), "too late in the file")
            t.expect(!IntroLearning.isIntroSkip(from: 120, to: 60), "backwards")
            t.expect(!IntroLearning.isIntroSkip(from: 60, to: 65), "five seconds is a nudge")
            t.expect(!IntroLearning.isIntroSkip(from: 30, to: 600), "nine minutes is not an intro")
        }

        t.test("skipping a ninety-second opening is") {
            t.expect(IntroLearning.isIntroSkip(from: 95, to: 185))
            // A cold open before the titles is the common anime shape.
            t.expect(IntroLearning.isIntroSkip(from: 160, to: 250))
        }

        t.test("one skip is recorded but not yet offered") {
            let first = IntroLearning.merge(nil, from: 90, to: 180)
            t.expectEqual(first.samples, 1)
            // One skip is an action; acting on it would put a wrong button on
            // every show where somebody once jumped a slow scene.
            t.expect(!IntroLearning.shouldOffer(first, at: 95))
        }

        t.test("two skips in the same place agree, and the window averages") {
            var intro = IntroLearning.merge(nil, from: 90, to: 180)
            intro = IntroLearning.merge(intro, from: 94, to: 184)
            t.expectEqual(intro.samples, 2)
            t.expectEqual(intro.start, 92)
            t.expectEqual(intro.end, 182)
            t.expect(IntroLearning.shouldOffer(intro, at: 95))
        }

        t.test("a single odd skip replaces a guess but never a pattern") {
            // One sample has no standing to outvote a fresh observation.
            let guess = IntroLearning.merge(nil, from: 90, to: 180)
            let replaced = IntroLearning.merge(guess, from: 20, to: 60)
            t.expectEqual(replaced.start, 20)
            t.expectEqual(replaced.samples, 1)

            // Two do. Episode nine's odd skip must not discard what the first
            // eight agreed on.
            var settled = IntroLearning.merge(nil, from: 90, to: 180)
            settled = IntroLearning.merge(settled, from: 90, to: 180)
            let kept = IntroLearning.merge(settled, from: 20, to: 60)
            t.expectEqual(kept.start, 90)
            t.expectEqual(kept.samples, 2)
        }

        t.test("the offer covers the window and stops at its end") {
            var intro = IntroLearning.merge(nil, from: 90, to: 180)
            intro = IntroLearning.merge(intro, from: 90, to: 180)
            // A little before, because the estimate is an average and the real
            // boundary moves between episodes.
            t.expect(IntroLearning.shouldOffer(intro, at: 82))
            t.expect(IntroLearning.shouldOffer(intro, at: 150))
            // Never past the end: skipping then would jump out of the episode
            // you are already watching.
            t.expect(!IntroLearning.shouldOffer(intro, at: 181))
            t.expect(!IntroLearning.shouldOffer(intro, at: 40))
        }

        t.test("nothing learned offers nothing") {
            t.expect(!IntroLearning.shouldOffer(nil, at: 90))
        }
    }
}

/// The learned intro, through the real database rather than in memory.
@MainActor
func registerIntroStorageTests(_ t: TestRunner) async {

    func makeRepository() throws -> LibraryRepository {
        let database = try LibraryDatabase(inMemory: true)
        let session = JellyfinSession(
            serverURL: URL(string: "http://demo.local")!,
            serverName: "Test", serverId: "s1",
            userId: "u1", userName: "test", deviceId: "d1"
        )
        // Storage only; the client is never reached.
        return LibraryRepository(database: database, client: JellyfinClient(session: session, token: "t"))
    }

    await t.suite("Learned intro storage") { t in

        await t.test("nothing is known about a series nobody has skipped in") {
            let repository = try makeRepository()
            t.expectNil(try await repository.learnedIntro(seriesId: "show"))
        }

        await t.test("two skips are recorded and read back") {
            let repository = try makeRepository()
            _ = try await repository.recordIntroSkip(seriesId: "show", from: 90, to: 180)
            let merged = try await repository.recordIntroSkip(seriesId: "show", from: 94, to: 184)
            t.expectEqual(merged.samples, 2)

            let stored = try await repository.learnedIntro(seriesId: "show")
            t.expectEqual(stored?.samples, 2)
            t.expectEqual(stored?.start, 92)
            t.expectEqual(stored?.end, 182)
        }

        await t.test("each series learns on its own") {
            let repository = try makeRepository()
            _ = try await repository.recordIntroSkip(seriesId: "a", from: 90, to: 180)
            _ = try await repository.recordIntroSkip(seriesId: "b", from: 20, to: 60)
            t.expectEqual(try await repository.learnedIntro(seriesId: "a")?.start, 90)
            t.expectEqual(try await repository.learnedIntro(seriesId: "b")?.start, 20)
        }

        await t.test("a series can be forgotten") {
            let repository = try makeRepository()
            _ = try await repository.recordIntroSkip(seriesId: "show", from: 90, to: 180)
            try await repository.forgetIntro(seriesId: "show")
            t.expectNil(try await repository.learnedIntro(seriesId: "show"))
        }
    }
}

/// What a change announcement carries.
@MainActor
func registerLibraryChangeTests(_ t: TestRunner) {

    t.suite("Library change") { t in

        t.test("a watch-state change names the row and no library") {
            let change = LibraryChange(reason: "watch state", itemId: "e1")
            t.expectEqual(change.itemId, "e1")
            // Nil, so a grid refreshes one row rather than reloading — which is
            // what keeps the reader's place while a tick changes.
            t.expectNil(change.libraryId)
        }

        t.test("a sync names the library and no row") {
            let change = LibraryChange(reason: "library synced", itemId: nil, libraryId: "anime")
            t.expectEqual(change.libraryId, "anime")
            // New titles cannot be refreshed one row at a time: the rows are not
            // there yet, so the page has to reload.
            t.expectNil(change.itemId)
        }
    }
}
