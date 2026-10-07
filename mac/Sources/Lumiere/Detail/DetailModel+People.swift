import Foundation
import Observation
import LumiereKit

/// Credits by role. Split from DetailModel.swift for the 300-line rule.
extension DetailModel {
    func people(type: String) -> [String] {
        (detail?.people ?? [])
            .filter { $0.type == type }
            .compactMap(\.name)
    }

    /// File size of the chosen version, for the technical panel.
    var fileSizeText: String? {
        guard let bytes = selectedSource?.size, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var bitrateText: String? {
        guard let bitrate = selectedSource?.bitrate, bitrate > 0 else { return nil }
        return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
    }
}
