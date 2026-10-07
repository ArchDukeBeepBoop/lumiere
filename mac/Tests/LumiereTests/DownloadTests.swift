import Foundation
import TestKit
import LumiereKit

/// Offline copies, and the two claims that matter most about them: that a download
/// fetches the original bytes rather than a transcode, and that "downloaded" is
/// never asserted about a file that is not on disk.
@MainActor
func registerDownloadTests(_ t: TestRunner) {

    let session = JellyfinSession(
        serverURL: URL(string: "http://192.168.50.15:8096")!,
        serverName: "Test", serverId: "s1",
        userId: "u1", userName: "test", deviceId: "d1"
    )
    let client = JellyfinClient(session: session, token: "tok")

    t.suite("Downloads") { t in

        t.test("the download URL asks for the original file, not a transcode") {
            // static=true is what makes Jellyfin serve bytes off disk. Without it a
            // download would store a re-encoded copy that is worse than the source.
            let url = client.downloadURL(itemId: "abc").absoluteString
            t.expect(url.contains("/Videos/abc/stream"), url)
            t.expect(url.contains("static=true"), "missing static=true: \(url)")
        }

        t.test("progress is nil until the size is known, rather than faked") {
            // Jellyfin does not always send Content-Length for a direct stream, and a
            // bar that invents a denominator lies about how long is left.
            var record = DownloadRecord(itemId: "a", serverId: "s1", requestedAt: Date())
            t.expect(record.fraction == nil, "expected no fraction without a total")
            record.totalBytes = 200
            record.receivedBytes = 50
            t.expectEqual(record.fraction, 0.25)
        }

        t.test("progress cannot exceed 1 even if more arrives than promised") {
            var record = DownloadRecord(itemId: "a", serverId: "s1", requestedAt: Date())
            record.totalBytes = 100
            record.receivedBytes = 150
            t.expectEqual(record.fraction, 1)
        }

        t.test("a complete record whose file is gone is not playable offline") {
            // The row outliving the file is the normal case after a user clears
            // space; a "Downloaded" badge over a missing file is worse than none.
            var record = DownloadRecord(itemId: "a", serverId: "s1", requestedAt: Date())
            record.state = .complete
            record.localPath = "/nonexistent/definitely-not-here.media"
            t.expect(!record.isPlayableOffline)
        }

        t.test("a queued or failed record is never playable offline") {
            var record = DownloadRecord(itemId: "a", serverId: "s1", requestedAt: Date())
            record.localPath = "/tmp"
            for state in [DownloadRecord.State.queued, .downloading, .failed] {
                record.state = state
                t.expect(!record.isPlayableOffline, "\(state) claimed to be playable")
            }
        }

        t.test("downloads live outside Caches, which the system may evict") {
            // A file the user explicitly asked for vanishing under disk pressure is
            // data loss from their point of view.
            let path = try DownloadManager.defaultDirectory().path
            t.expect(!path.contains("/Caches/"), "downloads are in Caches: \(path)")
            t.expect(path.contains("Application Support"), path)
        }
    }
}
