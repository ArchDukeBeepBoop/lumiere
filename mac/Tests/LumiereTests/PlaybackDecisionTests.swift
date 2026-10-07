import Foundation
import TestKit
import LumiereKit

/// The truth table.
///
/// Every case here is a file shape that exists in real libraries. The headline
/// assertion is the same throughout: the server must not be asked to transcode
/// something mpv could have played. If this suite goes green and the Jellyfin
/// dashboard still says "Transcoding", the bug is downstream of here.
// Shared by both halves of the decision tests.

// The machine Lumiere actually runs on.
let intel = SystemCapabilities(
    hardwareH264: true, hardwareHEVC: true, hardwareHEVC10Bit: true,
    hardwareVP9: false, hardwareAV1: false, dolbyVision: false,
    maxDecodeWidth: 4096, architecture: "x86_64"
)
let appleSilicon = SystemCapabilities(
    hardwareH264: true, hardwareHEVC: true, hardwareHEVC10Bit: true,
    hardwareVP9: true, hardwareAV1: true, dolbyVision: true,
    maxDecodeWidth: 4096, architecture: "arm64"
)

func decide(
    _ source: MediaSource,
    _ capabilities: SystemCapabilities = intel,
    _ options: PlaybackPlanner.Options = .init()
) -> PlaybackDecision {
    PlaybackPlanner.decide(source: source, capabilities: capabilities, options: options)
}


@MainActor
func registerPlaybackDecisionTests(_ t: TestRunner) {
    // MARK: - What AVPlayer should take

    t.suite("Playback decision · AVPlayer path") { t in

        t.test("MP4 H.264 AAC is the plain case") {
            let decision = decide(source(container: "mp4", video: h264(), audio: aac()))
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .avPlayer)
            t.expectEqual(decision.reason, .nativelySupported)
        }

        t.test("MOV and M4V are taken as readily as MP4") {
            for container in ["mov", "m4v", "MP4"] {
                let decision = decide(source(container: container, video: h264(), audio: aac()))
                t.expectEqual(decision.engine, .avPlayer, "container \(container)")
            }
        }

        t.test("MP4 HEVC direct plays, but on mpv rather than AVPlayer") {
            // The engine moved deliberately. AVFoundation takes HEVC in MP4 only
            // with an `hvc1` sample entry and refuses `hev1` outright — measured
            // on a real file, where the video track reports isDecodable = false
            // while its AAC track plays. Nothing in Jellyfin's metadata says which
            // spelling a file uses, so the engine that plays both is the only one
            // that can be chosen honestly. Direct play either way: no transcode.
            let decision = decide(source(
                container: "mp4",
                video: hevc(bitDepth: 10, range: "HDR10"),
                audio: eac3()
            ))
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .mpv)
        }

        t.test("AC3 and ALAC are fine for AVFoundation") {
            for codec in ["ac3", "alac", "mp3"] {
                let decision = decide(source(
                    container: "mp4", video: h264(), audio: audio(codec: codec)
                ))
                t.expectEqual(decision.engine, .avPlayer, "audio \(codec)")
            }
        }

        t.test("a file with no audio track at all still plays") {
            let decision = decide(source(container: "mp4", video: h264(), audio: nil))
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .avPlayer)
        }

        t.test("subtitles that need no rendering do not push it to mpv") {
            let decision = decide(
                source(
                    container: "mp4", video: h264(), audio: aac(),
                    subtitles: [subtitle(index: 3, codec: "subrip")]
                ),
                intel,
                .init(selectedSubtitleIndex: 3)
            )
            t.expectEqual(decision.engine, .avPlayer)
        }

        t.test("unselected bitmap subtitles are irrelevant") {
            // A PGS track present but not chosen must not cost the AVPlayer path.
            let decision = decide(source(
                container: "mp4", video: h264(), audio: aac(),
                subtitles: [subtitle(index: 3, codec: "pgssub")]
            ))
            t.expectEqual(decision.engine, .avPlayer)
        }
    }

    // MARK: - What mpv must take

    t.suite("Playback decision · mpv path") { t in

        t.test("MKV goes to mpv whatever is inside it") {
            let decision = decide(source(container: "mkv", video: h264(), audio: aac()))
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .mpv)
            t.expectEqual(decision.reason, .containerUnsupportedByAVFoundation)
        }

        t.test("the flagship case: 4K HEVC Dolby Vision TrueHD MKV direct plays") {
            // A UHD Blu-ray rip. Every other client transcodes this; Lumiere must not.
            let decision = decide(source(
                container: "mkv",
                video: hevc(bitDepth: 10, range: "DOVI", dvProfile: 5, width: 3840, height: 2160),
                audio: truehd(),
                subtitles: [subtitle(index: 3, codec: "pgssub")]
            ))
            t.expectEqual(decision.route, .directPlay)
            t.expectEqual(decision.engine, .mpv)
            t.expect(decision.toneMapDolbyVision, "profile 5 on Intel must tone-map")
            t.expectEqual(decision.badgeText, "Direct play")
        }

        t.test("DTS, TrueHD, FLAC and Opus all route to mpv even in an MP4") {
            for codec in ["dts", "truehd", "flac", "opus", "vorbis", "dtshd"] {
                let decision = decide(source(
                    container: "mp4", video: h264(), audio: audio(codec: codec)
                ))
                t.expectEqual(decision.engine, .mpv, "audio \(codec)")
                t.expectEqual(decision.route, .directPlay, "audio \(codec)")
                t.expectEqual(decision.reason, .audioCodecUnsupportedByAVFoundation, "audio \(codec)")
            }
        }

        t.test("VP9 and AV1 route to mpv on this Intel Mac") {
            for codec in ["vp9", "av1"] {
                let decision = decide(source(
                    container: "mp4", video: video(codec: codec), audio: aac()
                ))
                t.expectEqual(decision.engine, .mpv, "video \(codec)")
                t.expect(decision.softwareDecode, "\(codec) has no hardware path here")
            }
        }

        t.test("AV1 stays on AVPlayer where there is hardware for it") {
            let decision = decide(
                source(container: "mp4", video: video(codec: "av1"), audio: aac()),
                appleSilicon
            )
            t.expectEqual(decision.engine, .avPlayer)
            t.expect(!decision.softwareDecode)
        }

        t.test("12-bit HEVC needs mpv even though 10-bit does not") {
            let decision = decide(source(
                container: "mp4", video: hevc(bitDepth: 12), audio: aac()
            ))
            t.expectEqual(decision.engine, .mpv)
            t.expectEqual(decision.reason, .videoCodecUnsupportedByAVFoundation)
        }

        t.test("VC-1 and MPEG-2 route to mpv and are flagged as software") {
            for codec in ["vc1", "mpeg2video"] {
                let decision = decide(source(
                    container: "mkv", video: video(codec: codec), audio: ac3()
                ))
                t.expectEqual(decision.engine, .mpv, "video \(codec)")
                t.expect(decision.softwareDecode, "\(codec) should warn about CPU")
            }
        }

        t.test("selecting a PGS subtitle moves an otherwise-AVPlayer file to mpv") {
            let decision = decide(
                source(
                    container: "mp4", video: h264(), audio: aac(),
                    subtitles: [subtitle(index: 2, codec: "pgssub")]
                ),
                intel,
                .init(selectedSubtitleIndex: 2)
            )
            t.expectEqual(decision.engine, .mpv)
            t.expectEqual(decision.reason, .subtitleNeedsRendering)
            t.expectEqual(decision.route, .directPlay)
        }

        t.test("styled ASS subtitles also need mpv") {
            for codec in ["ass", "ssa", "vobsub", "dvdsub"] {
                let decision = decide(
                    source(
                        container: "mp4", video: h264(), audio: aac(),
                        subtitles: [subtitle(index: 2, codec: codec)]
                    ),
                    intel,
                    .init(selectedSubtitleIndex: 2)
                )
                t.expectEqual(decision.reason, .subtitleNeedsRendering, "subtitle \(codec)")
            }
        }

        t.test("Dolby Vision profile 8 also tone-maps on Intel") {
            let decision = decide(source(
                container: "mp4", video: hevc(bitDepth: 10, range: "DOVI", dvProfile: 8), audio: aac()
            ))
            t.expectEqual(decision.engine, .mpv)
            t.expect(decision.toneMapDolbyVision)
        }

        t.test("Dolby Vision is left alone where it is actually supported") {
            let decision = decide(
                source(
                    container: "mp4",
                    video: hevc(bitDepth: 10, range: "DOVI", dvProfile: 8),
                    audio: aac()
                ),
                appleSilicon
            )
            // The claim here is about tone mapping, not about the engine: a
            // machine that presents Dolby Vision natively must not have profile 8
            // flattened to HDR10 on the way. Which engine carries it is the
            // container question settled above.
            t.expect(!decision.toneMapDolbyVision)
        }

        t.test("a DV profile with no range type is still detected") {
            let decision = decide(source(
                container: "mp4", video: hevc(bitDepth: 10, range: "HDR", dvProfile: 5), audio: aac()
            ))
            t.expect(decision.toneMapDolbyVision)
        }

        t.test("HDR10 and HLG are not mistaken for Dolby Vision") {
            for range in ["HDR10", "HLG", "HDR10Plus"] {
                let decision = decide(source(
                    container: "mp4", video: hevc(bitDepth: 10, range: range), audio: aac()
                ))
                t.expect(!decision.toneMapDolbyVision, "range \(range)")
            }
        }
    }
}
