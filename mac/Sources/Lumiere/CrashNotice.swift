import AppKit
import LumiereKit

/// "Lumiere quit unexpectedly last time" — said at the next launch, with the
/// report one click away, rather than leaving a crash to be noticed or not.
/// macOS writes the report; this only notices a new one.
@MainActor
enum CrashNotice {
    private static let seenKey = "crashNoticeSeen"

    static func check(_ app: AppModel) {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        let seen = UserDefaults.standard.object(forKey: seenKey) as? Date ?? Date()
        UserDefaults.standard.set(Date(), forKey: seenKey)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let newest = files
            .filter { $0.lastPathComponent.hasPrefix("Lumiere-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate, date > seen else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }
        guard let (report, _) = newest else { return }
        Diagnostics.log("[crash] found \(report.lastPathComponent)")
        app.report("Lumiere quit unexpectedly last time.", actionTitle: "Show Report") {
            NSWorkspace.shared.activateFileViewerSelecting([report])
        }
    }
}
