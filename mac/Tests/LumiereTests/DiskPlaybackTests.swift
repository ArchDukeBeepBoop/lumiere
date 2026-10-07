import Foundation
import TestKit
import LumiereKit

/// Opening the server's file directly rather than streaming it.
@MainActor
func registerDiskPlaybackTests(_ t: TestRunner) {

    t.suite("Disk playback") { t in

        t.test("a readable direct-play file is opened from disk") {
            let url = DiskPlayback.fileURL(
                path: "/Volumes/M/film.mkv", directPlay: true, enabled: true, isReadable: { _ in true }
            )
            t.expectEqual(url?.path, "/Volumes/M/film.mkv")
            t.expect(url?.isFileURL == true)
        }

        t.test("a remux or transcode always streams") {
            t.expectEqual(DiskPlayback.fileURL(
                path: "/Volumes/M/film.mkv", directPlay: false, enabled: true, isReadable: { _ in true }
            ), nil)
        }

        t.test("an unreadable or missing path streams") {
            t.expectEqual(DiskPlayback.fileURL(
                path: "/Volumes/Gone/film.mkv", directPlay: true, enabled: true, isReadable: { _ in false }
            ), nil)
            t.expectEqual(DiskPlayback.fileURL(
                path: nil, directPlay: true, enabled: true, isReadable: { _ in true }
            ), nil)
            t.expectEqual(DiskPlayback.fileURL(
                path: "", directPlay: true, enabled: true, isReadable: { _ in true }
            ), nil)
        }

        t.test("the preference turns it off") {
            t.expectEqual(DiskPlayback.fileURL(
                path: "/Volumes/M/film.mkv", directPlay: true, enabled: false, isReadable: { _ in true }
            ), nil)
        }
    }
}
