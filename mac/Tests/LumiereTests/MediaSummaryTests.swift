import Foundation
import TestKit
import LumiereKit

@MainActor
func registerMediaSummaryTests(_ t: TestRunner) {

    func stream(_ json: [String: Any]) -> MediaStream {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JellyfinClient.decoder.decode(MediaStream.self, from: data)
    }

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

    t.suite("Resolution labels") { t in

        t.test("standard resolutions") {
            t.expectEqual(MediaSummary.resolutionLabel(width: 3840, height: 2160), "4K")
            t.expectEqual(MediaSummary.resolutionLabel(width: 1920, height: 1080), "1080p")
            t.expectEqual(MediaSummary.resolutionLabel(width: 1280, height: 720), "720p")
            t.expectEqual(MediaSummary.resolutionLabel(width: 720, height: 576), "SD")
        }

        t.test("a cropped 4K scope film is still 4K") {
            // 3840x1600 is a 2.40:1 film with the bars removed. Matching on
            // height would call this 1080p, which is the bug this rule exists for.
            t.expectEqual(MediaSummary.resolutionLabel(width: 3840, height: 1600), "4K")
        }

        t.test("a cropped 1080p scope film is still 1080p") {
            t.expectEqual(MediaSummary.resolutionLabel(width: 1920, height: 800), "1080p")
        }

        t.test("DCI 4K counts as 4K") {
            t.expectEqual(MediaSummary.resolutionLabel(width: 4096, height: 2160), "4K")
        }

        t.test("1440p is distinguished from 1080p and 4K") {
            t.expectEqual(MediaSummary.resolutionLabel(width: 2560, height: 1440), "1440p")
        }

        t.test("missing or zero dimensions yield no label") {
            t.expectNil(MediaSummary.resolutionLabel(width: nil, height: 1080))
            t.expectNil(MediaSummary.resolutionLabel(width: 1920, height: nil))
            t.expectNil(MediaSummary.resolutionLabel(width: 0, height: 0))
        }
    }

    t.suite("HDR labels") { t in

        t.test("Dolby Vision reads as tone-mapped on a Mac that cannot present it") {
            let dv = stream(["Index": 0, "Type": "Video", "VideoRangeType": "DOVI", "DvProfile": 5])
            t.expectEqual(
                MediaSummary.rangeLabel(for: dv, dolbyVisionSupported: intel.dolbyVision),
                "DV → HDR10"
            )
        }

        t.test("Dolby Vision reads as itself where it is actually supported") {
            let dv = stream(["Index": 0, "Type": "Video", "VideoRangeType": "DOVI", "DvProfile": 8])
            t.expectEqual(
                MediaSummary.rangeLabel(for: dv, dolbyVisionSupported: appleSilicon.dolbyVision),
                "Dolby Vision"
            )
        }

        t.test("a DV profile alone is enough, even without the range type") {
            // Some servers report DvProfile but leave VideoRangeType as plain HDR.
            let dv = stream(["Index": 0, "Type": "Video", "VideoRange": "HDR", "DvProfile": 5])
            t.expectEqual(
                MediaSummary.rangeLabel(for: dv, dolbyVisionSupported: false),
                "DV → HDR10"
            )
        }

        t.test("HDR10, HDR10+ and HLG are distinguished") {
            t.expectEqual(
                MediaSummary.rangeLabel(
                    for: stream(["Index": 0, "Type": "Video", "VideoRangeType": "HDR10"]),
                    dolbyVisionSupported: false
                ),
                "HDR10"
            )
            t.expectEqual(
                MediaSummary.rangeLabel(
                    for: stream(["Index": 0, "Type": "Video", "VideoRangeType": "HDR10Plus"]),
                    dolbyVisionSupported: false
                ),
                "HDR10+"
            )
            t.expectEqual(
                MediaSummary.rangeLabel(
                    for: stream(["Index": 0, "Type": "Video", "VideoRangeType": "HLG"]),
                    dolbyVisionSupported: false
                ),
                "HLG"
            )
        }

        t.test("SDR gets no HDR badge at all") {
            t.expectNil(MediaSummary.rangeLabel(
                for: stream(["Index": 0, "Type": "Video", "VideoRange": "SDR"]),
                dolbyVisionSupported: true
            ))
            t.expectNil(MediaSummary.rangeLabel(
                for: stream(["Index": 0, "Type": "Video"]),
                dolbyVisionSupported: true
            ))
        }
    }

    t.suite("Codec and channel names") { t in

        t.test("codecs read as people write them") {
            t.expectEqual(MediaSummary.normalise(codec: "hevc"), "HEVC")
            t.expectEqual(MediaSummary.normalise(codec: "h264"), "H.264")
            t.expectEqual(MediaSummary.normalise(codec: "truehd"), "TrueHD")
            t.expectEqual(MediaSummary.normalise(codec: "dtshd"), "DTS-HD")
            t.expectEqual(MediaSummary.normalise(codec: "pgssub"), "PGS")
            t.expectEqual(MediaSummary.normalise(codec: "subrip"), "SRT")
            t.expectEqual(MediaSummary.normalise(codec: "vc1"), "VC-1")
        }

        t.test("an unknown codec is passed through rather than hidden") {
            t.expectEqual(MediaSummary.normalise(codec: "prores"), "PRORES")
        }

        t.test("an empty codec stays empty") {
            t.expectEqual(MediaSummary.normalise(codec: ""), "")
        }

        t.test("the server's channel layout wins when present") {
            let audio = stream([
                "Index": 1, "Type": "Audio", "Channels": 8, "ChannelLayout": "7.1",
            ])
            t.expectEqual(MediaSummary.channelLabel(for: audio), "7.1")
        }

        t.test("channel count is used when no layout is given") {
            t.expectEqual(
                MediaSummary.channelLabel(for: stream(["Index": 1, "Type": "Audio", "Channels": 6])),
                "5.1"
            )
            t.expectEqual(
                MediaSummary.channelLabel(for: stream(["Index": 1, "Type": "Audio", "Channels": 2])),
                "Stereo"
            )
            t.expectEqual(
                MediaSummary.channelLabel(for: stream(["Index": 1, "Type": "Audio", "Channels": 1])),
                "Mono"
            )
        }

        t.test("an unusual channel count yields no label rather than a wrong one") {
            t.expectEqual(
                MediaSummary.channelLabel(for: stream(["Index": 1, "Type": "Audio", "Channels": 3])),
                ""
            )
        }
    }

    t.suite("Hardware decode reporting") { t in

        t.test("this Intel Mac reports HEVC and H.264 in hardware") {
            t.expect(MediaSummary.decodesInHardware(codec: "hevc", capabilities: intel))
            t.expect(MediaSummary.decodesInHardware(codec: "h264", capabilities: intel))
        }

        t.test("this Intel Mac reports VP9 and AV1 as software") {
            t.expect(!MediaSummary.decodesInHardware(codec: "vp9", capabilities: intel))
            t.expect(!MediaSummary.decodesInHardware(codec: "av1", capabilities: intel))
        }

        t.test("Apple silicon reports VP9 and AV1 in hardware") {
            t.expect(MediaSummary.decodesInHardware(codec: "vp9", capabilities: appleSilicon))
            t.expect(MediaSummary.decodesInHardware(codec: "av1", capabilities: appleSilicon))
        }

        t.test("an unknown or missing codec counts as software, never as hardware") {
            t.expect(!MediaSummary.decodesInHardware(codec: "vc1", capabilities: appleSilicon))
            t.expect(!MediaSummary.decodesInHardware(codec: nil, capabilities: appleSilicon))
        }
    }
}
