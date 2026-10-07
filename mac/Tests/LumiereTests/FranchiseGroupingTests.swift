import Foundation
import TestKit
import LumiereKit

/// Grouping titles by what relates them rather than by what they are called.
@MainActor
func registerFranchiseGroupingTests(_ t: TestRunner) {

    func title(
        _ id: String,
        _ name: String,
        tags: [String] = [],
        creators: [String] = [],
        studios: [String] = []
    ) -> RelationCandidate {
        RelationCandidate(id: id, name: name, tags: tags, creators: creators, studios: studios)
    }

    t.suite("Franchise grouping") { t in

        t.test("titles sharing nothing are never grouped") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "Cowboy Bebop", tags: ["space western"]),
                title("2", "Perfect Blue", tags: ["psychological"]),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("a shared tag groups titles with nothing in common by name") {
            // The case the whole feature exists for: no shared word between them.
            let groups = FranchiseGrouping.groups(from: [
                title("1", "Code Geass", tags: ["code geass"]),
                title("2", "Akito the Exiled", tags: ["code geass"]),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 2)
            t.expectEqual(groups[0].name, "Code Geass")
        }

        t.test("a shared original creator relates a franchise") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "Fate/Zero", creators: ["Kinoko Nasu"]),
                title("2", "Unlimited Blade Works", creators: ["Kinoko Nasu"]),
                title("3", "Heaven's Feel", creators: ["Kinoko Nasu"]),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 3)
            t.expectEqual(groups[0].name, "Kinoko Nasu")
        }

        t.test("a studio alone never forms a group") {
            // A studio's catalogue is not a collection — this is the signal most
            // likely to relate everything to everything if it were allowed to.
            let groups = FranchiseGrouping.groups(from: [
                title("1", "A", studios: ["Studio Ghibli"]),
                title("2", "B", studios: ["Studio Ghibli"]),
                title("3", "C", studios: ["Studio Ghibli"]),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("a studio corroborates a group it did not form") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "A", tags: ["monogatari"], studios: ["Shaft"]),
                title("2", "B", tags: ["monogatari"], studios: ["Shaft"]),
            ])
            t.expectEqual(groups.count, 1)
            t.expect(groups[0].reason.contains("Shaft"), "reason names the shared studio")
        }

        t.test("tags describing the whole library are ignored") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "A", tags: ["anime", "based on manga"]),
                title("2", "B", tags: ["anime", "based on manga"]),
                title("3", "C", tags: ["anime", "japan"]),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("a key covering too much is a genre, not a franchise") {
            // 14 titles sharing one tag: past the cap, so it describes a shelf.
            let wide = (1...14).map { title("\($0)", "T\($0)", tags: ["shounen"]) }
            t.expectEqual(FranchiseGrouping.groups(from: wide).count, 0)

            // The same tag on 12 is inside the cap and does group.
            let narrow = (1...12).map { title("\($0)", "T\($0)", tags: ["gundam"]) }
            t.expectEqual(FranchiseGrouping.groups(from: narrow).count, 1)
        }

        t.test("overlapping keys merge into one group, not two") {
            // Tag links 1–2, creator links 2–3. All three are one franchise.
            let groups = FranchiseGrouping.groups(from: [
                title("1", "A", tags: ["gundam"]),
                title("2", "B", tags: ["gundam"], creators: ["Yoshiyuki Tomino"]),
                title("3", "C", creators: ["Yoshiyuki Tomino"]),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 3)
        }

        t.test("a tag names the group ahead of a creator covering the same titles") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "A", tags: ["madoka magica"], creators: ["Gen Urobuchi"]),
                title("2", "B", tags: ["madoka magica"], creators: ["Gen Urobuchi"]),
            ])
            t.expectEqual(groups[0].name, "Madoka Magica")
        }

        t.test("results are ordered and stable across runs") {
            let candidates = [
                title("1", "A", tags: ["small"]),
                title("2", "B", tags: ["small"]),
                title("3", "C", tags: ["big"]),
                title("4", "D", tags: ["big"]),
                title("5", "E", tags: ["big"]),
            ]
            let first = FranchiseGrouping.groups(from: candidates)
            let second = FranchiseGrouping.groups(from: candidates)
            t.expectEqual(first.map(\.id), second.map(\.id))
            // Biggest first.
            t.expectEqual(first[0].itemIds.count, 3)
        }

        t.test("members are listed in a stable order too") {
            let groups = FranchiseGrouping.groups(from: [
                title("z", "Zeta", tags: ["gundam"]),
                title("a", "Alpha", tags: ["gundam"]),
            ])
            t.expectEqual(groups[0].itemIds, ["a", "z"])
        }

        t.test("an empty library proposes nothing") {
            t.expectEqual(FranchiseGrouping.groups(from: []).count, 0)
        }
    }
}

/// The prose signal: relating titles by what their synopses are about, for the
/// franchises no tag or credit ever labelled.
@MainActor
func registerProseGroupingTests(_ t: TestRunner) {

    func title(_ id: String, _ name: String, overview: String) -> RelationCandidate {
        RelationCandidate(
            id: id, name: name, tags: [], creators: [], studios: [], overview: overview
        )
    }

    t.suite("Prose grouping") { t in

        t.test("two synopses about the same thing group, with no shared title word") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "Fate/Zero", overview:
                    "Seven mages are summoned to fight. The prize is the Holy Grail War, "
                  + "and only one may survive to claim it."),
                title("2", "Unlimited Blade Works", overview:
                    "A student is drawn into the Holy Grail War, bound to a servant he "
                  + "does not understand."),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 2)
            t.expectEqual(groups[0].name, "Holy Grail War")
        }

        t.test("unrelated synopses stay apart") {
            let groups = FranchiseGrouping.groups(from: [
                title("1", "A", overview:
                    "A bounty hunter drifts across the solar system with an old debt "
                  + "and a dog he did not ask for."),
                title("2", "B", overview:
                    "A pop idol leaves her group for acting, and her sense of what is "
                  + "real starts to come apart."),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("a sentence's first word never starts a phrase") {
            // Capitalised by grammar, not by being a name. Without this, every
            // synopsis opening with the same word would relate to every other.
            let keys = FranchiseGrouping.proseKeys(in:
                "Something happens here to set the scene properly. Something else "
              + "follows it along afterwards in turn.")
            t.expect(!keys.contains("something else"), "sentence openings are skipped")
        }

        t.test("phrases never span a full stop") {
            let keys = FranchiseGrouping.proseKeys(in:
                "They fought through the long Winter. Koyomi Araragi returned to the "
              + "town he grew up in, changed by it.")
            t.expect(keys.contains("koyomi araragi"), "the real name is found")
            t.expect(!keys.contains("winter koyomi"), "a phrase never crosses a sentence")
        }

        t.test("a single capitalised word is not enough") {
            let keys = FranchiseGrouping.proseKeys(in:
                "The traveller reached Kyoto alone and waited there for a long while "
              + "without much to do at all.")
            t.expectEqual(keys.count, 0)
        }

        t.test("a synopsis too short to be distinctive yields nothing") {
            t.expectEqual(FranchiseGrouping.proseKeys(in: "A short one.").count, 0)
        }

        t.test("a tag still names the group ahead of a phrase") {
            let groups = FranchiseGrouping.groups(from: [
                RelationCandidate(
                    id: "1", name: "A", tags: ["monogatari"], creators: [], studios: [],
                    overview: "The story follows Koyomi Araragi through a long strange spring."
                ),
                RelationCandidate(
                    id: "2", name: "B", tags: ["monogatari"], creators: [], studios: [],
                    overview: "Again it follows Koyomi Araragi, now through a colder season."
                ),
            ])
            t.expectEqual(groups[0].name, "Monogatari")
        }
    }
}
