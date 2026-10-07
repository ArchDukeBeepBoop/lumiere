import Foundation
import VideoToolbox
import CoreMedia

/// What this specific Mac can decode in hardware.
///
/// This is the `capabilities` half of the playback decision. It is resolved once
/// at launch and then treated as immutable — `PlaybackDecision` stays a pure
/// function by taking it as an argument rather than probing the system itself.
///
/// On the Intel Coffee Lake machine Lumiere targets, expect: H.264 yes,
/// HEVC 8-bit and 10-bit yes, VP9 8-bit yes, AV1 no, Dolby Vision no.
public struct SystemCapabilities: Sendable, Equatable {

    public let hardwareH264: Bool
    public let hardwareHEVC: Bool
    public let hardwareHEVC10Bit: Bool
    public let hardwareVP9: Bool
    public let hardwareAV1: Bool

    /// Apple silicon and recent Intel Macs with compatible displays can present
    /// Dolby Vision through AVFoundation. Everything else must tone-map.
    public let dolbyVision: Bool

    /// Maximum practical decode dimension. Coffee Lake Quick Sync handles 4K
    /// HEVC comfortably; 8K is software-only and not worth attempting.
    public let maxDecodeWidth: Int

    public let architecture: String

    public init(
        hardwareH264: Bool,
        hardwareHEVC: Bool,
        hardwareHEVC10Bit: Bool,
        hardwareVP9: Bool,
        hardwareAV1: Bool,
        dolbyVision: Bool,
        maxDecodeWidth: Int,
        architecture: String
    ) {
        self.hardwareH264 = hardwareH264
        self.hardwareHEVC = hardwareHEVC
        self.hardwareHEVC10Bit = hardwareHEVC10Bit
        self.hardwareVP9 = hardwareVP9
        self.hardwareAV1 = hardwareAV1
        self.dolbyVision = dolbyVision
        self.maxDecodeWidth = maxDecodeWidth
        self.architecture = architecture
    }

    /// Probes VideoToolbox for what the current machine actually supports.
    ///
    /// `VTIsHardwareDecodeSupported` answers for the codec family only — it cannot
    /// distinguish 8-bit from 10-bit HEVC. Every Mac that reports HEVC hardware
    /// decode has handled Main10 since Kaby Lake, so the two are tied together
    /// here; if a machine is ever found where that is false, this is the seam.
    public static func detect() -> SystemCapabilities {
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let arch = currentArchitecture()

        return SystemCapabilities(
            hardwareH264: VTIsHardwareDecodeSupported(kCMVideoCodecType_H264),
            hardwareHEVC: hevc,
            hardwareHEVC10Bit: hevc,
            hardwareVP9: VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9),
            hardwareAV1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
            // Dolby Vision presentation requires Apple silicon media engines.
            // Intel Macs get HDR10 tone mapping through mpv instead.
            dolbyVision: arch == "arm64",
            maxDecodeWidth: 4096,
            architecture: arch
        )
    }

    private static func currentArchitecture() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            Array(raw.prefix(while: { $0 != 0 }))
        }
        return String(decoding: machine, as: UTF8.self)
    }

    /// One-line human summary, used by the diagnostics panel and the launch log.
    public var summary: String {
        var supported: [String] = []
        if hardwareH264 { supported.append("H.264") }
        if hardwareHEVC { supported.append("HEVC") }
        if hardwareHEVC10Bit { supported.append("HEVC 10-bit") }
        if hardwareVP9 { supported.append("VP9") }
        if hardwareAV1 { supported.append("AV1") }
        let list = supported.isEmpty ? "none" : supported.joined(separator: ", ")
        return "\(architecture) · hardware decode: \(list) · Dolby Vision: \(dolbyVision ? "yes" : "tone-mapped")"
    }
}
