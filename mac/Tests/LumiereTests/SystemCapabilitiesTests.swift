import TestKit
import LumiereKit

@MainActor
func registerSystemCapabilitiesTests(_ t: TestRunner) {
    t.suite("System capabilities") { t in

        t.test("detection returns a plausible architecture") {
            let caps = SystemCapabilities.detect()
            t.expect(
                ["x86_64", "arm64"].contains(caps.architecture),
                "unexpected architecture \(caps.architecture)"
            )
        }

        t.test("every Mac decodes H.264 in hardware") {
            // True for every Mac that can run macOS 14. If this fails, the
            // VideoToolbox probe is wrong, not the machine.
            t.expect(SystemCapabilities.detect().hardwareH264)
        }

        t.test("HEVC 10-bit tracks HEVC support") {
            let caps = SystemCapabilities.detect()
            t.expectEqual(caps.hardwareHEVC10Bit, caps.hardwareHEVC)
        }

        t.test("Dolby Vision is never native on Intel") {
            let caps = SystemCapabilities.detect()
            if caps.architecture == "x86_64" {
                t.expectEqual(caps.dolbyVision, false)
            }
        }

        t.test("summary names each supported codec") {
            let caps = SystemCapabilities(
                hardwareH264: true,
                hardwareHEVC: true,
                hardwareHEVC10Bit: true,
                hardwareVP9: false,
                hardwareAV1: false,
                dolbyVision: false,
                maxDecodeWidth: 4096,
                architecture: "x86_64"
            )
            t.expect(caps.summary.contains("H.264"))
            t.expect(caps.summary.contains("HEVC"))
            t.expect(!caps.summary.contains("AV1"), "AV1 should be absent")
            t.expect(caps.summary.contains("tone-mapped"))
        }

        t.test("summary reports none when nothing is supported") {
            let caps = SystemCapabilities(
                hardwareH264: false,
                hardwareHEVC: false,
                hardwareHEVC10Bit: false,
                hardwareVP9: false,
                hardwareAV1: false,
                dolbyVision: false,
                maxDecodeWidth: 4096,
                architecture: "x86_64"
            )
            t.expect(caps.summary.contains("hardware decode: none"))
        }

        t.test("Apple silicon reports native Dolby Vision") {
            let caps = SystemCapabilities(
                hardwareH264: true,
                hardwareHEVC: true,
                hardwareHEVC10Bit: true,
                hardwareVP9: true,
                hardwareAV1: true,
                dolbyVision: true,
                maxDecodeWidth: 4096,
                architecture: "arm64"
            )
            t.expect(caps.summary.contains("Dolby Vision: yes"))
        }
    }
}
