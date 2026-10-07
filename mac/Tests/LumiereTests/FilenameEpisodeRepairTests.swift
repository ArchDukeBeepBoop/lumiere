import Foundation
import TestKit
import LumiereKit

/// Rebuilding a collapsed series from its filenames.
///
/// Every path here is real. The library had 118 files under one series carrying 15
/// distinct names, with sixteen separate files each claiming season 1 episode 1 —
/// so the parsing has to be right on exactly these shapes, not on tidy ones.
@MainActor
func registerFilenameEpisodeRepairTests(_ t: TestRunner) {

    let root = "/Volumes/Media/Anime/Monogatari (2009)"

    t.suite("Filename episode repair") { t in

        t.test("the arc, number and title all come out of one path") {
            let path = "\(root)/Monogatari Series First Season (2009)"
                     + "/Nisemonogatari (2012)/Nisemonogatari - 1x11 - Tsukihi Phoenix, Part 4.mkv"
            let arc = FilenameEpisodeRepair.arcName(from: path)
            t.expectEqual(arc?.name, "Nisemonogatari")
            t.expectEqual(arc?.year, 2012)
            t.expectEqual(
                FilenameEpisodeRepair.episodeTitle(from: path), "Tsukihi Phoenix, Part 4"
            )
        }

        t.test("an arc whose own name contains separators still parses") {
            // "Monogatari - Off & Monster Season - 1x01 - Orokamonogatari" splits
            // into four parts; counting separators would take the wrong one.
            let path = "\(root)/Monogatari - Off & Monster Season (2024)"
                     + "/Monogatari - Off & Monster Season - 1x01 - Orokamonogatari: Tsukihi Undo.mkv"
            t.expectEqual(
                FilenameEpisodeRepair.arcName(from: path)?.name,
                "Monogatari - Off & Monster Season"
            )
            t.expectEqual(
                FilenameEpisodeRepair.episodeTitle(from: path),
                "Orokamonogatari: Tsukihi Undo"
            )
        }

        t.test("each arc becomes its own season, in release order") {
            // The collision, resolved: three files all called episode 1 become
            // episode 1 of three different seasons.
            let proposals = FilenameEpisodeRepair.proposals(for: [
                (id: "nise", path: "\(root)/Nisemonogatari (2012)/Nisemonogatari - 1x01 - Amber Bee, Part 1.mkv"),
                (id: "bake", path: "\(root)/Bakemonogatari (2009)/Bakemonogatari - 1x01 - Hitagi Crab - Part 1.mkv"),
                (id: "kizu", path: "\(root)/Kizumonogatari (2016)/Kizumonogatari - 1x01 - Tekketsu-hen.mkv"),
            ])
            t.expectEqual(proposals.count, 3)
            // Ordered by the year in the folder, not alphabetically.
            t.expectEqual(proposals.map(\.id), ["bake", "nise", "kizu"])
            t.expectEqual(proposals.map(\.season), [1, 2, 3])
            t.expectEqual(Set(proposals.map(\.episode)), [1])
        }

        t.test("episodes of one arc keep their own numbers") {
            let proposals = FilenameEpisodeRepair.proposals(for: [
                (id: "e11", path: "\(root)/Nisemonogatari (2012)/Nisemonogatari - 1x11 - Tsukihi Phoenix, Part 4.mkv"),
                (id: "e10", path: "\(root)/Nisemonogatari (2012)/Nisemonogatari - 1x10 - Tsukihi Phoenix, Part 3.mkv"),
            ])
            t.expectEqual(proposals.map(\.episode), [10, 11])
            t.expectEqual(Set(proposals.map(\.season)), [1])
        }

        t.test("the real titles replace the duplicated one") {
            let proposals = FilenameEpisodeRepair.proposals(for: [
                (id: "a", path: "\(root)/Kabukimonogatari (2013)/Kabukimonogatari - 1x01 - Mayoi Jiangshi, Part 1.mkv"),
                (id: "b", path: "\(root)/Otorimonogatari (2013)/Otorimonogatari - 1x01 - Nadeko Medusa, Part 1.mkv"),
            ])
            t.expectEqual(
                proposals.map(\.title), ["Mayoi Jiangshi, Part 1", "Nadeko Medusa, Part 1"]
            )
        }

        t.test("a folder with no year still yields an arc") {
            let proposals = FilenameEpisodeRepair.proposals(for: [
                (id: "x", path: "\(root)/Extras/Show - 1x02 - Something.mkv"),
            ])
            t.expectEqual(proposals.first?.arc, "Extras")
            t.expectNil(proposals.first?.year)
        }

        t.test("a file with no numbering is left alone, not guessed at") {
            let proposals = FilenameEpisodeRepair.proposals(for: [
                (id: "x", path: "\(root)/Bakemonogatari (2009)/Bakemonogatari NCOP.mkv"),
                (id: "y", path: nil),
            ])
            t.expectEqual(proposals.count, 0)
        }

        t.test("a half episode is reported, not folded onto its neighbour") {
            // Real file. Taking the 6 from "1x06.5" would recreate the collision
            // this whole thing exists to remove.
            let plan = FilenameEpisodeRepair.plan(for: [
                (id: "six", path: "\(root)/Monogatari - Off & Monster Season (2024)"
                                + "/Monogatari - Off & Monster Season - 1x06 - Real.mkv"),
                (id: "half", path: "\(root)/Monogatari - Off & Monster Season (2024)"
                                 + "/Monogatari - Off & Monster Season - 1x06.5 - Special.mkv"),
            ])
            t.expectEqual(plan.proposals.map(\.id), ["six"])
            t.expectEqual(plan.skipped.map(\.id), ["half"])
            t.expect(plan.skipped.first?.reason.contains("half episode") == true)
        }

        t.test("a file with no marker is skipped for a different reason") {
            let plan = FilenameEpisodeRepair.plan(for: [
                (id: "ncop", path: "\(root)/Bakemonogatari (2009)/Bakemonogatari NCOP.mkv"),
            ])
            t.expectEqual(plan.proposals.count, 0)
            t.expect(plan.skipped.first?.reason.contains("1x04") == true)
        }

        t.test("results are stable across runs") {
            let files = [
                (id: "a", path: "\(root)/Onimonogatari (2013)/Onimonogatari - 1x01 - Shinobu Time, Part 1.mkv"),
                (id: "b", path: "\(root)/Koimonogatari (2013)/Koimonogatari - 1x01 - Hitagi End, Part 1.mkv"),
            ]
            // Same year: the tie breaks on name, so the order cannot drift.
            t.expectEqual(
                FilenameEpisodeRepair.proposals(for: files).map(\.id),
                FilenameEpisodeRepair.proposals(for: files).map(\.id)
            )
        }
    }

    // Season resolution across the shapes a real library actually contains. Every
    // folder layout below was taken from the library this was written against.
    t.suite("Merged season resolution") { t in

        func files(_ entries: [(String, String)]) -> [(id: String, path: String?)] {
            entries.enumerated().map { index, entry in
                (id: "\(index)", path: "/Anime/\(entry.0)/\(entry.1)")
            }
        }

        t.test("a normal show is left exactly as its filenames say") {
            // Nothing collides, so nothing is resolved — and a show whose seasons
            // are already right must never be renumbered by folder order.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 1", "Show - 1x01 - One.mkv"),
                ("Season 2", "Show - 2x01 - Two.mkv"),
                ("Season 10", "Show - 10x01 - Ten.mkv"),
            ]))
            t.expect(!plan.resolvedSeasons)
            t.expectEqual(plan.proposals.map(\.season), [1, 2, 10])
        }

        t.test("folders that name their season keep it, however the files number") {
            // Kingdom Edge: "Season 3 - Utsukushiki Toushi-tachi" whose files all
            // say 1x01, beside a Season 1 that also says 1x01.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 1 - Rurou no Senshi", "QB - 1x01 - Exiled.mkv"),
                ("Season 3 - Utsukushiki Toushi-tachi", "QB - 1x01 - Beautiful.mkv"),
                ("Season 5 - Rebellion", "QB - 1x01 - Rebellion.mkv"),
            ]))
            t.expect(plan.resolvedSeasons)
            t.expectEqual(plan.proposals.map(\.season), [1, 3, 5])
        }

        t.test("unnumbered folders go after the numbered ones, in release order") {
            // JoJo: four numbered seasons plus two OVA folders dated in brackets.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 1 - Phantom Blood", "JoJo - 1x01 - Blood.mkv"),
                ("Season 2 - Stardust Crusaders", "JoJo - 2x01 - Stardust.mkv"),
                ("OVAs (2000)", "JoJo - 2x01 - OVA 2000.mkv"),
                ("OVAs (1993)", "JoJo - 1x01 - OVA 1993.mkv"),
            ]))
            t.expectEqual(plan.proposals.map(\.season), [1, 2, 3, 4])
            t.expectEqual(plan.proposals.map(\.arc), [
                "Season 1 - Phantom Blood", "Season 2 - Stardust Crusaders",
                "OVAs", "OVAs",
            ])
            // 1993 before 2000, not alphabetically and not by discovery order.
            t.expectEqual(plan.proposals.last?.year, 2000)
        }

        t.test("a season split into cours is not a collision") {
            // Haikyu!!: "Season 4" holds 1-13 and "Season 4 2nd-cour" holds 14-25.
            // One season in two folders. Renumbering either invents a season.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 4", "H - 4x13 - Thirteen.mkv"),
                ("Season 4 2nd-cour", "H - 4x14 - Fourteen.mkv"),
            ]))
            t.expect(!plan.resolvedSeasons)
            t.expectEqual(plan.proposals.map(\.season), [4, 4])
        }

        t.test("a folder holding two seasons is refused, not guessed at") {
            // FBI: a stray 5x01 sitting in the Season 4 folder. Taking the folder's
            // word would stamp it with a number season 4 already has.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 4", "FBI - 4x01 - Four.mkv"),
                ("Season 4", "FBI - 5x01 - Stray.mkv"),
                ("Season 5", "FBI - 5x01 - Five.mkv"),
            ]))
            t.expectEqual(plan.proposals.count, 1)
            t.expect(plan.skipped.contains { $0.reason.contains("more than one season") })
        }

        t.test("folders nothing can separate are refused rather than half-fixed") {
            // The Devil Is a Part-Timer: "Season 2" and "Season 2 Part 1" both hold
            // an episode 11, and every signal says both are season 2.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 2", "Devil - 2x11 - Eleven.mkv"),
                ("Season 2 Part 1", "Devil - 2x11 - Eleven again.mkv"),
                ("Season 3", "Devil - 3x01 - Three.mkv"),
            ]))
            t.expectEqual(plan.proposals.map(\.season), [3])
            t.expect(plan.skipped.contains { $0.reason.contains("still shares") })
        }

        t.test("\"Second Season\" is not a season number") {
            // Real folders: "Owarimonogatari Second Season" and "Monogatari - Off &
            // Monster Season". A looser rule reads a number into both.
            t.expectNil(FilenameEpisodeRepair.statedSeason(in: "Owarimonogatari Second Season"))
            t.expectNil(FilenameEpisodeRepair.statedSeason(in: "Monogatari - Off & Monster Season"))
            t.expectEqual(FilenameEpisodeRepair.statedSeason(in: "Season 01"), 1)
            t.expectEqual(FilenameEpisodeRepair.statedSeason(in: "Season 4 - Kingdom Edge OVAs"), 4)
        }

        t.test("a marker inside the show's own name is not the episode number") {
            // Real series. Scanning the filename left to right finds "3x3" in the
            // title first, so every one of these parsed as season 3 episode 3 and
            // the repair would have collapsed four episodes onto one number.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("3x3 Eyes (1991)", "3x3 Eyes - 1x01 - Transmigration.mkv"),
                ("3x3 Eyes (1991)", "3x3 Eyes - 1x02 - Yakumo.mkv"),
                ("3x3 Eyes (1991)", "3x3 Eyes - 2x01 - Descent.mkv"),
            ]))
            t.expectEqual(plan.proposals.map(\.episode), [1, 2, 1])
            t.expectEqual(plan.proposals.map(\.season), [1, 1, 2])
        }

        t.test("S01E02 is read when it stands as its own part") {
            t.expectEqual(FilenameEpisodeRepair.markerNumbers("S01E02")?.season, 1)
            t.expectEqual(FilenameEpisodeRepair.markerNumbers("S01E02")?.episode, 2)
            t.expectEqual(FilenameEpisodeRepair.markerNumbers("1x04")?.episode, 4)
            // Not markers: a show's name, a resolution, an ordinary word.
            t.expectNil(FilenameEpisodeRepair.markerNumbers("3x3 Eyes"))
            t.expectNil(FilenameEpisodeRepair.markerNumbers("1920x1080"))
            t.expectNil(FilenameEpisodeRepair.markerNumbers("Sacrifice"))
        }

        t.test("an absolutely-numbered show has nothing to read and is untouched") {
            // One Piece, Naruto, Detective Conan — no marker, so no proposal. This
            // is the property that makes a library-wide sweep safe.
            let plan = FilenameEpisodeRepair.plan(for: files([
                ("Season 01 - East Blue", "One Piece - 101 - Showdown.mkv"),
                ("NCOP", "01 - R★O★C★K★S.mkv"),
            ]))
            t.expectEqual(plan.proposals.count, 0)
        }
    }

}
