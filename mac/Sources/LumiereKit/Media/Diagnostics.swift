import Foundation

/// The app's running notes: to standard error as always, and to a small file
/// that outlives the session.
///
/// Standard error goes nowhere when the app is opened from the Dock, so every
/// timing and every sync note it wrote was lost the moment it was written —
/// and the only way to read one was to launch the app from a terminal, which is
/// no use for "how slow was the home screen yesterday". The file is
/// `~/Library/Logs/Lumiere/lumiere.log`, rotated at 2 MB with one old copy
/// kept, so it never grows past 4 MB. It stays on this Mac.
public enum Diagnostics {

    public static func log(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
        writer.append(message)
    }

    /// Where the file lives, for Settings and for anyone reading it.
    public static var fileURL: URL { writer.url }

    private static let writer = LogFile()
}

/// Appends on a serial queue, so a burst of notes from several tasks never
/// interleaves mid-line and never holds up the caller.
private final class LogFile: @unchecked Sendable {
    // @unchecked: every mutable touch happens on `queue`.
    let url: URL
    private let queue = DispatchQueue(label: "lumiere.diagnostics", qos: .utility)
    private let limit = 2 * 1024 * 1024
    private var handle: FileHandle?

    init() {
        // The test suite writes notes too; they belong nowhere near the real log.
        let isTest = ProcessInfo.processInfo.processName.hasSuffix("Tests")
        let dir = isTest
            ? FileManager.default.temporaryDirectory.appendingPathComponent("lumiere-test-logs")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Lumiere")
        url = dir.appendingPathComponent("lumiere.log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func append(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        queue.async { [self] in
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
            }
            guard let handle, let data = "\(stamp) \(message)\n".data(using: .utf8) else { return }
            try? handle.write(contentsOf: data)
            if let size = try? handle.offset(), size > limit { rotate() }
        }
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let old = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
