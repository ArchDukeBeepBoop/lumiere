import Foundation

/// Whether an episode is in Specials because it was a loose file.
///
/// The server files a file left in a show's own folder, beside its season
/// folders, under Specials (scanner/seat.go). Shown as such it could look
/// arbitrary — "why is this OVA under Extras?" — so the page says where it was
/// found. Told from the path alone: a season-0 episode whose folder names no
/// season. Pure.
public enum LoosePlacement {
    private static let seasonFolder = try! NSRegularExpression(
        pattern: #"^(?:season|series|s)\s*0*\d{1,3}\b|^specials?$|^extras?$|^ova$"#,
        options: .caseInsensitive
    )

    public static func wasLoose(season: Int?, path: String?) -> Bool {
        guard season == 0, let path, !path.isEmpty else { return false }
        let folder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let range = NSRange(folder.startIndex..., in: folder)
        return seasonFolder.firstMatch(in: folder, range: range) == nil
    }
}
