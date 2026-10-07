import SwiftUI
import LumiereKit

/// The version picker and the Play label. Split from DetailHeader.swift for
/// the 300-line rule.
extension DetailHeader {
    /// Only appears when a title genuinely has more than one file — a 4K and a
    /// 1080p rip of the same film.
    var versionPicker: some View {
        Picker("Version", selection: Binding(
            get: { model.selectedSourceId ?? "" },
            set: { model.selectedSourceId = $0 }
        )) {
            ForEach(model.detail?.mediaSources ?? []) { source in
                Text(versionLabel(source)).tag(source.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    func versionLabel(_ source: MediaSource) -> String {
        var parts: [String] = []
        if let resolution = BadgeBuilder.resolutionLabel(
            width: source.videoStream?.width, height: source.videoStream?.height
        ) {
            parts.append(resolution)
        }
        if let codec = source.videoStream?.codec {
            parts.append(BadgeBuilder.normalise(codec: codec))
        }
        if let size = source.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.isEmpty ? (source.name ?? "Version") : parts.joined(separator: " · ")
    }

    var playLabel: String {
        guard let userData = entry.userData, userData.isInProgress else { return "Play" }
        let seconds = Int(userData.resumeSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "Resume %d:%02d:%02d", hours, minutes, secs)
            : String(format: "Resume %d:%02d", minutes, secs)
    }
}
