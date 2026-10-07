import Foundation
import AppKit
import CMPV
import LumiereKit

/// The C-facing half of `MPVEngine`: option and property plumbing, event
/// translation, and the view mpv draws into. Split out to keep the engine itself
/// readable as playback logic.
extension MPVEngine {

    // MARK: - Options and properties

    func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        let status = name.withCString { key in
            value.withCString { val in
                mpv_set_option_string(handle, key, val)
            }
        }
        // A rejected option is why a video output silently does nothing. Never
        // discard the status.
        if status < 0 {
            Diagnostics.log("[mpv] option \(name)=\(value) rejected: \(errorText(status))")
        }
    }

    func setProperty(_ name: String, _ value: String) {
        guard let handle else { return }
        let status = name.withCString { key in
            value.withCString { val in
                mpv_set_property_string(handle, key, val)
            }
        }
        if status < 0 {
            Diagnostics.log("[mpv] property \(name)=\(value) rejected: \(errorText(status))")
        }
    }

    func errorText(_ code: Int32) -> String {
        mpv_error_string(code).map { String(cString: $0) } ?? "error \(code)"
    }

    func stringProperty(_ name: String) -> String? {
        guard let handle else { return nil }
        guard let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    func intProperty(_ name: String) -> Int64? {
        guard let handle else { return nil }
        var value: Int64 = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return value
    }

    func doubleProperty(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value: Double = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 else { return nil }
        return value
    }

    func command(_ arguments: [String]) {
        guard let handle else { return }
        command(arguments, on: handle)
    }

    /// Queues a command and returns at once. mpv copies the arguments before
    /// returning, so the strings need only outlive the call.
    ///
    /// For the transport commands issued while a hand is on a control — a seek
    /// per drag event — where a synchronous `mpv_command` would park the main
    /// thread until the core got round to it, and the core is sometimes busy
    /// for longer than a frame.
    func commandAsync(_ arguments: [String]) {
        guard let handle else { return }
        command(arguments, on: handle, async: true)
    }

    func command(_ arguments: [String], on handle: OpaquePointer, async: Bool = false) {
        // mpv wants a NULL-terminated array of C strings that outlive the call.
        // strdup'd rather than borrowed from Swift Strings, whose buffers are
        // only valid inside `withCString`.
        let owned: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        defer { owned.forEach { free($0) } }

        var borrowed: [UnsafePointer<CChar>?] = owned.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        borrowed.append(nil)
        let status = borrowed.withUnsafeMutableBufferPointer { buffer in
            async ? mpv_command_async(handle, 0, buffer.baseAddress)
                  : mpv_command(handle, buffer.baseAddress)
        }
        if status < 0 {
            Diagnostics.log(
                "[mpv] command \(arguments.first ?? "?") failed: \(errorText(status))"
            )
        }
    }

    /// Routes mpv's own log lines into the app's diagnostics.
    ///
    /// Without this, a failure inside mpv — a video output that cannot
    /// initialise, a codec it will not open — is completely silent, which is how
    /// this engine first appeared to "work" while decoding nothing.
    func forwardLogMessages(_ message: String, level: String) {
        Diagnostics.log("[mpv/\(level)] \(message.trimmingCharacters(in: .newlines))")
    }

    // MARK: - Track list

    /// Reads mpv's track list into the engine-neutral `MediaTrack` shape.
    ///
    /// Track ids here are mpv's own (`aid`/`sid`), not array indices — selecting
    /// by position would pick the wrong stream on any file whose tracks are not
    /// numbered consecutively, which is most remuxes.
    func reloadTracks() {
        guard let count = intProperty("track-list/count"), count > 0 else {
            cachedAudioTracks = []
            cachedSubtitleTracks = []
            return
        }

        var audio: [MediaTrack] = []
        var subtitles: [MediaTrack] = []

        for index in 0..<Int(count) {
            let type = stringProperty("track-list/\(index)/type") ?? ""
            guard type == "audio" || type == "sub" else { continue }

            let id = Int(stringProperty("track-list/\(index)/id") ?? "") ?? index
            let language = stringProperty("track-list/\(index)/lang")
            let codec = stringProperty("track-list/\(index)/codec")
            let title = stringProperty("track-list/\(index)/title")
            let channels = Int(stringProperty("track-list/\(index)/demux-channel-count") ?? "")
            let isDefault = stringProperty("track-list/\(index)/default") == "yes"
            let isForced = stringProperty("track-list/\(index)/forced") == "yes"

            let track = MediaTrack(
                id: id,
                title: displayTitle(
                    title: title, language: language, codec: codec,
                    channels: channels, type: type, id: id
                ),
                language: language,
                codec: codec.map { MediaSummary.normalise(codec: $0) },
                channels: channels,
                isDefault: isDefault,
                isForced: isForced
            )

            if type == "audio" { audio.append(track) } else { subtitles.append(track) }
        }

        cachedAudioTracks = audio
        cachedSubtitleTracks = subtitles
    }

    private func displayTitle(
        title: String?, language: String?, codec: String?,
        channels: Int?, type: String, id: Int
    ) -> String {
        if let title, !title.isEmpty { return title }

        var parts: [String] = []
        if let language, !language.isEmpty { parts.append(language.uppercased()) }
        if let codec, !codec.isEmpty { parts.append(MediaSummary.normalise(codec: codec)) }
        if type == "audio", let channels {
            switch channels {
            case 8: parts.append("7.1")
            case 6: parts.append("5.1")
            case 2: parts.append("Stereo")
            case 1: parts.append("Mono")
            default: break
            }
        }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }
}

/// Carries the mpv handle onto the event thread.
///
/// `OpaquePointer` is not Sendable, and libmpv's contract is specific: every API
/// call is thread-safe except `mpv_wait_event`, which must be serialised per
/// handle. Only the event pump calls it, so this is stating a documented
/// invariant rather than waiving one.
struct MPVHandleBox: @unchecked Sendable {
    let raw: OpaquePointer
}

/// A libmpv event, translated into something Sendable before it crosses threads.
///
/// The raw `mpv_event` and its payload are only valid until the next
/// `mpv_wait_event` on that handle, so nothing may hold on to the pointer.
enum MPVEvent: Sendable {
    case timePosition(Double)
    case duration(Double)
    case paused(Bool)
    case endReached
    case tracksChanged
    case fileLoaded
    /// mpv has finished a seek and is showing the frame it landed on.
    case playbackRestarted
    case error(String)
    case logMessage(String, String)
    case ignored

    init(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let raw = event.data?.assumingMemoryBound(to: mpv_event_property.self) else {
                self = .ignored
                return
            }
            let property = raw.pointee
            let name = property.name.map { String(cString: $0) } ?? ""

            switch (name, property.format) {
            case ("time-pos", MPV_FORMAT_DOUBLE):
                self = .timePosition(property.data?.assumingMemoryBound(to: Double.self).pointee ?? 0)
            case ("duration", MPV_FORMAT_DOUBLE):
                self = .duration(property.data?.assumingMemoryBound(to: Double.self).pointee ?? 0)
            case ("pause", MPV_FORMAT_FLAG):
                self = .paused((property.data?.assumingMemoryBound(to: Int32.self).pointee ?? 0) != 0)
            case ("eof-reached", MPV_FORMAT_FLAG):
                let reached = (property.data?.assumingMemoryBound(to: Int32.self).pointee ?? 0) != 0
                self = reached ? .endReached : .ignored
            case ("track-list/count", MPV_FORMAT_INT64):
                self = .tracksChanged
            default:
                self = .ignored
            }

        case MPV_EVENT_LOG_MESSAGE:
            guard let raw = event.data?.assumingMemoryBound(to: mpv_event_log_message.self) else {
                self = .ignored
                return
            }
            let text = raw.pointee.text.map { String(cString: $0) } ?? ""
            let level = raw.pointee.level.map { String(cString: $0) } ?? "info"
            self = .logMessage(text, level)

        case MPV_EVENT_FILE_LOADED:
            self = .fileLoaded

        case MPV_EVENT_PLAYBACK_RESTART:
            self = .playbackRestarted

        case MPV_EVENT_END_FILE:
            guard let raw = event.data?.assumingMemoryBound(to: mpv_event_end_file.self) else {
                self = .ignored
                return
            }
            switch raw.pointee.reason {
            case MPV_END_FILE_REASON_EOF:
                self = .endReached
            case MPV_END_FILE_REASON_ERROR:
                let code = raw.pointee.error
                let message = mpv_error_string(code).map { String(cString: $0) } ?? "unknown error"
                self = .error(message)
            default:
                self = .ignored
            }

        default:
            self = .ignored
        }
    }
}
