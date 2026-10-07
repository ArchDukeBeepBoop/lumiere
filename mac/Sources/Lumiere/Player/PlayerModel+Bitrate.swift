import Foundation

/// The one place the bitrate cap is read.
///
/// Split from PlayerModel+Session.swift for the project's 300-line limit, and it
/// earns a file: this value has to reach three places that were written at three
/// different times, and the bug it fixes was exactly one of them missing it.
extension PlayerModel {

    /// The user's bitrate cap in bits per second, or nil for unlimited.
    ///
    /// One definition, read by all three places that need it — the decision, the
    /// PlaybackInfo request and the stream URL. It used to be read in `start` and
    /// nowhere else, which is how the cap came to decide *whether* to transcode
    /// while saying nothing about *to what*: the traffic carried no
    /// `MaxStreamingBitrate` and no `videoBitRate`, so the server re-encoded at its
    /// own default — measured at roughly 5 Mbps against a 1 Mbps cap. Someone
    /// capping their bitrate to protect a slow connection got a transcode that
    /// ignored the cap entirely.
    ///
    /// Not private: PlayerModel+Session.swift reads it, and Swift scopes
    /// `private` to the file.
    static var bitrateCap: Int? {
        let mbps = UserDefaults.standard.double(forKey: "maxBitrateMbps")
        return mbps > 0 ? Int(mbps * 1_000_000) : nil
    }
}
