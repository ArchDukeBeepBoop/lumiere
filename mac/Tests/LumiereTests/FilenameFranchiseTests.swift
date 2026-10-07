import Foundation
import TestKit
import LumiereKit

/// Finding franchises in names, for the libraries with no metadata to relate.
@MainActor
func registerFilenameFranchiseTests(_ t: TestRunner) {

    func title(_ id: String, _ name: String, path: String? = nil) -> FilenameFranchise.Candidate {
        FilenameFranchise.Candidate(id: id, name: name, path: path)
    }

    t.suite("Filename franchises") { t in

        t.test("Monogatari groups on a stem no prefix matcher would find") {
            // The case this exists for. Bake and Nise share no prefix; the shared
            // part is a suffix of both and a prefix of the third.
            let groups = FilenameFranchise.groups(from: [
                title("1", "Bakemonogatari"),
                title("2", "Nisemonogatari"),
                title("3", "Monogatari Series Second Season"),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 3)
            t.expect(groups[0].name.lowercased().contains("monogatari"),
                     "named after the stem, got \(groups[0].name)")
        }

        t.test("Fate groups on a whole word") {
            let groups = FilenameFranchise.groups(from: [
                title("1", "Fate/Zero"),
                title("2", "Fate/stay night: Unlimited Blade Works"),
                title("3", "Fate/Apocrypha"),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 3)
            t.expectEqual(groups[0].name, "Fate")
        }

        t.test("Tenchi groups across its many sub-titles") {
            let groups = FilenameFranchise.groups(from: [
                title("1", "Tenchi Muyo! Ryo-Ohki"),
                title("2", "Tenchi Universe"),
                title("3", "Tenchi in Tokyo"),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 3)
        }

        t.test("unrelated titles are never grouped") {
            let groups = FilenameFranchise.groups(from: [
                title("1", "Cowboy Bebop"),
                title("2", "Perfect Blue"),
                title("3", "Paprika"),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("release noise never forms a franchise") {
            // Every file in a library carries these; grouping on them would put the
            // whole library in one collection.
            let groups = FilenameFranchise.groups(from: [
                title("1", "Kaiba (1080p BluRay x265 FLAC)"),
                title("2", "Texhnolyze (1080p BluRay x265 FLAC)"),
                title("3", "Dennou Coil (1080p BluRay x265 FLAC)"),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("a folder name relates titles the scraper mismatched") {
            // The folder is often the only correct name in the system.
            let groups = FilenameFranchise.groups(from: [
                title("1", "Unmatched Title", path: "/Anime/Gundam/Zeta/ep01.mkv"),
                title("2", "Another Wrong Name", path: "/Anime/Gundam/Wing/ep01.mkv"),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].name, "Gundam")
        }

        t.test("the library root folder does not relate everything") {
            // "/Anime" and "/Volumes" sit on every path in the library.
            let groups = FilenameFranchise.groups(from: [
                title("1", "Alpha", path: "/Volumes/MEDIA/Anime/Alpha/ep01.mkv"),
                title("2", "Beta", path: "/Volumes/MEDIA/Anime/Beta/ep01.mkv"),
            ])
            t.expectEqual(groups.count, 0)
        }

        t.test("a title joins the largest franchise that claims it") {
            // Without this, "Fate/stay night" splits Fate into two half-groups.
            let groups = FilenameFranchise.groups(from: [
                title("1", "Fate/Zero"),
                title("2", "Fate/stay night"),
                title("3", "Fate/Apocrypha"),
                title("4", "Stay Awhile"),
            ])
            t.expectEqual(groups.count, 1)
            t.expectEqual(groups[0].itemIds.count, 3)
        }

        t.test("a key covering the whole library is discarded") {
            let many = (1...25).map { title("\($0)", "Precure Entry \($0)") }
            t.expectEqual(FilenameFranchise.groups(from: many).count, 0)
        }

        t.test("results are stable across runs") {
            let items = [
                title("b", "Bakemonogatari"), title("n", "Nisemonogatari"),
                title("f1", "Fate/Zero"), title("f2", "Fate/Apocrypha"),
            ]
            t.expectEqual(
                FilenameFranchise.groups(from: items).map(\.id),
                FilenameFranchise.groups(from: items).map(\.id)
            )
        }

        t.test("one title alone is not a franchise") {
            t.expectEqual(FilenameFranchise.groups(from: [title("1", "Bakemonogatari")]).count, 0)
            t.expectEqual(FilenameFranchise.groups(from: []).count, 0)
        }
    }
}
