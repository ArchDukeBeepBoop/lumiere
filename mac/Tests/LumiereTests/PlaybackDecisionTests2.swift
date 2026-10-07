import Foundation
import TestKit
import LumiereKit

/// Split from PlaybackDecisionTests.swift for the 300-line rule.
@MainActor
func registerPlaybackDecisionFallbackTests(_ t: TestRunner) {

    // MARK: - When the server must work

    t.suite("Playback decision · server fallbacks") { t in

        t.test("without mpv, an MKV falls all the way to a transcode") {
            // The whole reason libmpv is bundled. If this ever fires in practice,
            // the dylib failed to load and the user's server is paying for it.
            let decision = decide(
                source(container: "mkv", video: h264(), audio: aac()),
                intel,
                .init(mpvAvailable: false)
            )
            t.expectEqual(decision.route, .transcode)
            t.expectEqual(decision.badgeText, "Transcoding")
        }

        t.test("without mpv, an MP4 with AV-friendly streams still direct plays") {
            let decision = decide(
                source(container: "mp4", video: h264(), audio: aac()),
                intel,
                .init(mpvAvailable: false)
            )
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .avPlayer)
        }

        t.test("a bitrate cap forces a transcode, because no client can shrink a file") {
            let decision = decide(
                source(container: "mkv", video: h264(), audio: aac(), bitrate: 60_000_000),
                intel,
                .init(maxBitrate: 20_000_000)
            )
            t.expectEqual(decision.route, .transcode)
            t.expectEqual(decision.reason, .bitrateOverLimit)
        }

        t.test("a bitrate under the cap changes nothing") {
            let decision = decide(
                source(container: "mkv", video: h264(), audio: aac(), bitrate: 12_000_000),
                intel,
                .init(maxBitrate: 20_000_000)
            )
            t.expectEqual(decision.route, .directPlay)
        }

        t.test("no cap set means no cap applied") {
            let decision = decide(source(
                container: "mkv", video: h264(), audio: aac(), bitrate: 90_000_000
            ))
            t.expectEqual(decision.route, .directPlay)
        }

        t.test("8K is beyond this machine and goes to the server") {
            let decision = decide(source(
                container: "mkv", video: hevc(bitDepth: 10, width: 7680, height: 4320), audio: aac()
            ))
            t.expectEqual(decision.route, .transcode)
            t.expectEqual(decision.reason, .resolutionOverDecoderLimit)
        }

        t.test("4K is comfortably inside the limit") {
            let decision = decide(source(
                container: "mkv", video: hevc(bitDepth: 10, width: 3840, height: 2160), audio: aac()
            ))
            t.expectEqual(decision.route, .directPlay)
        }

        t.test("an explicit transcode request is honoured over everything") {
            let decision = decide(
                source(container: "mp4", video: h264(), audio: aac()),
                intel,
                .init(forceTranscode: true)
            )
            t.expectEqual(decision.route, .transcode)
            t.expectEqual(decision.reason, .userForcedTranscode)
        }

        t.test("the forced transcode outranks even a Dolby Vision tone-map") {
            let decision = decide(
                source(container: "mkv", video: hevc(bitDepth: 10, dvProfile: 5), audio: truehd()),
                intel,
                .init(forceTranscode: true)
            )
            t.expectEqual(decision.route, .transcode)
        }
    }

    // MARK: - Degenerate input

    t.suite("Playback decision · missing metadata") { t in

        t.test("a source with no streams at all does not crash and does not transcode") {
            let decision = decide(source(container: "mkv", video: nil, audio: nil))
            t.expectEqual(decision.engine, .mpv)
            t.expectEqual(decision.route, .directPlay)
        }

        t.test("an unknown container goes to mpv rather than the server") {
            for container in ["", "webm", "avi", "ts", "m2ts", "ogm", "wmv"] {
                let decision = decide(source(container: container, video: h264(), audio: aac()))
                t.expectEqual(decision.engine, .mpv, "container \(container)")
                t.expectEqual(decision.route, .directPlay, "container \(container)")
            }
        }

        t.test("a video stream with no codec named goes to mpv") {
            let decision = decide(source(
                container: "mp4", video: video(codec: nil), audio: aac()
            ))
            t.expectEqual(decision.engine, .mpv)
        }

        t.test("HEVC with no bit depth reported still direct plays") {
            // Missing metadata must never cost a transcode. It goes to mpv like
            // all HEVC, and the point of the case is the route, not the engine.
            let decision = decide(source(
                container: "mp4", video: hevc(bitDepth: nil), audio: aac()
            ))
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .mpv)
        }

        t.test("an hev1 MP4 never reaches AVPlayer, whatever the machine can decode") {
            // The regression this guards. Both machines report HEVC hardware
            // decode; neither may be used as a reason to hand HEVC to
            // AVFoundation, because the refusal is about the container's sample
            // entry and not about the decoder.
            for capabilities in [intel, appleSilicon] {
                let decision = decide(
                    source(container: "mp4", video: hevc(bitDepth: 10), audio: aac()),
                    capabilities
                )
                t.expectEqual(decision.engine, .mpv)
                t.expectEqual(decision.route, .directPlay)
            }
        }

        t.test("selecting a subtitle index that does not exist is ignored") {
            let decision = decide(
                source(container: "mp4", video: h264(), audio: aac()),
                intel,
                .init(selectedSubtitleIndex: 99)
            )
            t.expectEqual(decision.engine, .avPlayer)
        }

        t.test("codec casing from the server does not matter") {
            let decision = decide(source(
                container: "MKV", video: video(codec: "HEVC"), audio: audio(codec: "TrueHD")
            ))
            t.expectEqual(decision.engine, .mpv)
            t.expectEqual(decision.route, .directPlay)
        }
    }

    // MARK: - The property that matters

    t.suite("Playback decision · the direct-play guarantee") { t in

        t.test("with mpv present, no realistic library file is ever transcoded") {
            // The one invariant worth stating as a property rather than a case.
            let containers = ["mkv", "mp4", "mov", "avi", "ts", "m2ts", "webm", "m4v"]
            let videos = ["h264", "hevc", "av1", "vp9", "vc1", "mpeg2video"]
            let audios = ["aac", "ac3", "eac3", "dts", "dtshd", "truehd", "flac", "opus", "mp3"]

            var transcoded: [String] = []
            for container in containers {
                for videoCodec in videos {
                    for audioCodec in audios {
                        let decision = decide(source(
                            container: container,
                            video: video(codec: videoCodec, bitDepth: 10, width: 3840, height: 2160),
                            audio: audio(codec: audioCodec)
                        ))
                        if decision.route != .directPlay {
                            transcoded.append("\(container)/\(videoCodec)/\(audioCodec)")
                        }
                    }
                }
            }
            t.expect(
                transcoded.isEmpty,
                "these should have direct played: \(transcoded.prefix(5).joined(separator: ", "))"
            )
        }

        t.test("every direct play reports a badge the Jellyfin dashboard can agree with") {
            let decision = decide(source(container: "mkv", video: hevc(), audio: truehd()))
            t.expectEqual(decision.badgeText, "Direct play")
            t.expect(!decision.reason.explanation.isEmpty)
        }
    }
}
