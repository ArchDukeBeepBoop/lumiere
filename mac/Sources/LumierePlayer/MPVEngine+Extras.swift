import Foundation

/// The menu bar's extras: audio delay and screenshots.
extension MPVEngine {

    public func setABLoop(a: Double?, b: Double?) async {
        setProperty("ab-loop-a", a.map { String(format: "%.3f", $0) } ?? "no")
        setProperty("ab-loop-b", b.map { String(format: "%.3f", $0) } ?? "no")
    }

    public func setAudioDevice(uid: String?) async {
        setProperty("audio-device", uid.map { "coreaudio/" + $0 } ?? "auto")
    }

    public func setAudioDelay(_ seconds: Double) async {
        setProperty("audio-delay", String(format: "%.3f", max(-10, min(10, seconds))))
    }

    /// `subtitles` rather than `video`: the frame as it is seen, which is what
    /// someone taking a screenshot of a film means.
    public func saveScreenshot(to url: URL) async -> Bool {
        command(["screenshot-to-file", url.path, "subtitles"])
        // The command is synchronous in mpv's queue but the write can trail it.
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
