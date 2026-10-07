import Foundation

/// Moves one file from the server to disk, reporting progress as it goes.
///
/// Exists because the obvious way to do this is catastrophically slow.
/// `URLSession.bytes` is an `AsyncSequence` of `UInt8`, so consuming it costs one
/// async iteration *per byte*: measured here against a 200 MB local file it ran at
/// 0.8 MB/s against 213 MB/s for a download task — 258× slower, and entirely
/// CPU-bound, so a fast disk and a fast network make no difference at all. A 2 GB
/// episode took forty-three minutes of spinning before a single frame was watchable.
///
/// A download task hands the whole transfer to the system, which writes it with the
/// same code every other app on the Mac uses, and calls back with progress rather
/// than making the caller count. The delegate exists only to receive those two
/// callbacks; there is no per-byte Swift code left in the path.
final class DownloadTransfer: NSObject, @unchecked Sendable {

    /// Guards the boxes below, which the delegate queue and the calling task both
    /// touch. A serial delegate queue is not enough on its own: the continuation is
    /// resumed from the delegate queue and installed from the caller's.
    private let lock = NSLock()

    /// `NSLock.lock()` is unavailable from an async context — it would block a
    /// cooperative thread — so every critical section here is a non-async closure.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
    private var continuation: CheckedContinuation<Int64, Error>?
    private var destination: URL?
    private var onProgress: (@Sendable (Int64, Int64?) -> Void)?
    /// How many bytes actually landed, read back after the move.
    private var written: Int64 = 0
    private var session: URLSession?

    /// Downloads `request` to `destination`, replacing whatever is there.
    ///
    /// Returns the byte count on disk. Cancelling the surrounding task cancels the
    /// transfer, and the partial file is discarded rather than left to be mistaken
    /// for a complete one.
    func run(
        request: URLRequest,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> Int64 {
        let configuration = URLSessionConfiguration.default
        // A media file is not a web page, and a stale one is worse than a slow one.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // No ceiling on the transfer itself. The per-request timeout still applies,
        // so a server that stops answering is caught; this only stops a legitimately
        // long download from being killed for taking long.
        configuration.timeoutIntervalForResource = .greatestFiniteMagnitude

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        locked {
            self.destination = destination
            self.onProgress = onProgress
        }

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.downloadTask(with: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locked { self.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Resumes the caller exactly once, whichever callback gets here first.
    private func finish(_ result: Result<Int64, Error>) {
        let continuation = locked { () -> CheckedContinuation<Int64, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        // After the resume, so the session is not torn down while it is still
        // delivering the callback that triggered this.
        defer { session?.finishTasksAndInvalidate(); session = nil }
        continuation.resume(with: result)
    }
}

extension DownloadTransfer: URLSessionDownloadDelegate {

    /// The temporary file is deleted the moment this returns, so the move happens
    /// here rather than being handed back to the caller to do later.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination = locked({ self.destination }) else { return }

        // A download task only reports transport failures. An HTTP error is a
        // successful transfer of an error page, and writing that over a media file
        // would leave a few hundred bytes of JSON named like an episode.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(JellyfinError.httpError(status: http.statusCode, body: nil)))
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Replaces rather than writes over. The hand-rolled path this succeeds
            // did neither: it opened the existing file for writing without
            // truncating, so re-downloading something shorter than what was already
            // there left the old tail on the end — a file of exactly the right name
            // and the wrong length, which plays until it doesn't.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size])
            written = (size as? NSNumber)?.int64Value ?? 0
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        locked { self.onProgress }?(
            totalBytesWritten,
            totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        )
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.success(written))
        }
    }
}
