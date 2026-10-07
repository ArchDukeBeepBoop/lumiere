import Foundation
import LumiereKit
import LumierePlayer

/// Turning a decision into something an engine can open.
///
/// Split from PlayerModel+Session.swift for the project's 300-line limit. It is a
/// coherent piece on its own: three sources of bytes — a completed download, a
/// demo fixture, the server — and the rule that the first one wins.
extension PlayerModel {

    /// Builds the URL to hand the engine.
    ///
    /// In demo mode the media source points at a generated fixture on disk, so
    /// playback exercises the real engine over a real file with no server. Any
    /// other session goes through StreamBuilder as normal.
    /// Not private: PlayerModel+Session.swift calls it, and Swift scopes
    /// `private` to the file.
    func playbackRequest(
        for decision: PlaybackDecision,
        source: MediaSource,
        resumeAt: Double
    ) async -> PlaybackRequest? {
        let headers = await client.streamingHeaders

        // A finished download wins over the network, which is the entire point of
        // downloading. The decision made from the server's PlaybackInfo still holds:
        // `static=true` fetched the original bytes, so the local file has the same
        // container, codecs and tracks the engine was chosen for.
        if let local = try? await repository.completedDownload(for: itemId),
           let path = local.localPath {
            Diagnostics.log("[playback] \(itemId) playing the local copy")
            return PlaybackRequest(
                url: URL(fileURLWithPath: path),
                startAt: resumeAt,
                toneMapDolbyVision: decision.toneMapDolbyVision
            )
        }

        if client.session.serverId == DemoFixtures.serverId,
           let path = source.path,
           FileManager.default.fileExists(atPath: path) {
            return PlaybackRequest(
                url: URL(fileURLWithPath: path),
                startAt: resumeAt,
                toneMapDolbyVision: decision.toneMapDolbyVision
            )
        }

        // The server's own file, where this machine can read it. See
        // `DiskPlayback` for why: a seek over loopback HTTP costs four times
        // what the same seek costs off the disk.
        let fromDisk = Preference.playsFromDisk.value
        if let file = DiskPlayback.fileURL(
            path: source.path, directPlay: decision.route == .directPlay, enabled: fromDisk
        ) {
            Diagnostics.log("[playback] \(itemId) playing from disk")
            return PlaybackRequest(
                url: file,
                startAt: resumeAt,
                toneMapDolbyVision: decision.toneMapDolbyVision,
                linkedFiles: await linkedFileURLs(fromDisk: true)
            )
        }

        guard let stream = StreamBuilder.stream(
            for: decision,
            serverURL: client.session.serverURL,
            itemId: itemId,
            mediaSourceId: source.id,
            playSessionId: playSessionId,
            headers: headers,
            // The whole point of the cap. `StreamBuilder` has always put these in
            // the URL when given them and is tested for it; nothing ever gave it.
            maxBitrate: Self.bitrateCap,
            audioStreamIndex: startingTracks?.audioIndex,
            subtitleStreamIndex: startingTracks?.subtitleIndex
        ) else { return nil }

        return PlaybackRequest(
            url: stream.url,
            startAt: resumeAt,
            toneMapDolbyVision: decision.toneMapDolbyVision,
            httpHeaders: stream.headers,
            linkedFiles: await linkedFileURLs(fromDisk: false)
        )
    }

    /// The files this episode's ordered chapters borrow from, as URLs.
    ///
    /// Asked of the server once per play. Empty for almost every file, and
    /// empty by preference where the owner would rather the episode play as
    /// the file alone. Where a link resolves to nothing — the release's
    /// opening is not in the library — that is said once, because a silent
    /// skip is exactly what VLC does and exactly what nobody understands.
    /// From disk where the episode itself is, so the whole timeline is read
    /// the same way; a borrowed file the disk cannot offer falls back to the
    /// stream, since mpv can mix the two.
    func linkedFileURLs(fromDisk: Bool) async -> [URL] {
        guard Preference.followsLinkedChapters.value else { return [] }
        guard let linked = try? await client.linkedChapters(itemId: itemId), linked.ordered
        else { return [] }
        if linked.unresolved > 0 {
            Diagnostics.log("[playback] \(itemId) links \(linked.unresolved) segment(s) the library does not have")
            missingLinkedSegments = linked.unresolved
        }
        return linked.borrowed.compactMap { item in
            DiskPlayback.fileURL(path: item.path, directPlay: true, enabled: fromDisk)
                ?? StreamBuilder.linkedFileURL(serverURL: client.session.serverURL, itemId: item.id)
        }
    }
}
