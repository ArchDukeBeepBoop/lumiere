import Foundation

public extension PlaybackPlanner {

    struct Options: Sendable, Equatable {
        /// False only if libmpv failed to load, which turns a direct play into a
        /// server transcode — worth surfacing loudly if it ever happens.
        public var mpvAvailable: Bool
        /// The subtitle stream the user has chosen, if any.
        public var selectedSubtitleIndex: Int?
        /// Bits per second, from settings. Nil means unlimited, which is the
        /// right default on a LAN.
        public var maxBitrate: Int?
        public var forceTranscode: Bool
        /// mpv plays even what AVFoundation could — Settings › Playback ›
        /// Engine, on by default. False keeps AVFoundation for the files it
        /// can open, and mpv for the rest.
        public var prefersMPV: Bool

        public init(
            mpvAvailable: Bool = true,
            selectedSubtitleIndex: Int? = nil,
            maxBitrate: Int? = nil,
            forceTranscode: Bool = false,
            prefersMPV: Bool = false
        ) {
            self.mpvAvailable = mpvAvailable
            self.selectedSubtitleIndex = selectedSubtitleIndex
            self.maxBitrate = maxBitrate
            self.forceTranscode = forceTranscode
            self.prefersMPV = prefersMPV
        }
    }
}
