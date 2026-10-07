import Foundation

/// Whether a file the server would stream can be opened straight from disk.
///
/// The server is on this machine by design, and the library is a volume this
/// machine can read. Streaming it back through HTTP costs a connection per
/// seek — and on this Mac the application firewall vets every connection to
/// the server, so a keyframe seek on a 4K film measured 620 ms over loopback
/// against 140 ms off the file. mpv reads a file it is handed directly with
/// none of that in the way.
///
/// Only for a direct play: a remux or a transcode is the server doing work
/// the file itself cannot. And only where the path is readable *now* — a
/// volume that is not mounted is a server's job to answer for, not a
/// silent failure to open.
public enum DiskPlayback {

    /// The file URL to open, or nil to stream.
    public static func fileURL(
        path: String?,
        directPlay: Bool,
        enabled: Bool,
        isReadable: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }
    ) -> URL? {
        guard enabled, directPlay, let path, !path.isEmpty, isReadable(path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
