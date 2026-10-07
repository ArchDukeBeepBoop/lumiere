import Foundation

/// A title's extras, sorted into what they are and named plainly.
///
/// One strip used to hold everything — "ACCA 13-Territory Inspection Dept. -
/// SP04" beside "… - Opening" beside a trailer — named after its file. Grouped,
/// an anime's openings sit together, its specials in order, a film's trailers
/// apart from its featurettes; and each is named for what it is, the show's
/// name taken off the front and "SP04" read as "Special 4". Pure.
public enum ExtrasGrouping {

    public struct Group: Identifiable, Sendable {
        public let title: String
        public let entries: [LibraryEntry]
        public var id: String { title }
    }

    /// In the order a person browses them.
    static let order = ["Openings", "Endings", "Specials", "Trailers", "Featurettes",
                        "Behind the Scenes", "Deleted Scenes", "Interviews", "Extras"]

    public static func groups(_ entries: [LibraryEntry], showName: String) -> [Group] {
        var buckets: [String: [LibraryEntry]] = [:]
        for entry in entries {
            buckets[kind(of: entry), default: []].append(entry)
        }
        return order.compactMap { title in
            guard let list = buckets[title], !list.isEmpty else { return nil }
            return Group(title: title, entries: list.sorted {
                name(of: $0, showName: showName)
                    .localizedStandardCompare(name(of: $1, showName: showName)) == .orderedAscending
            })
        }
    }

    static func kind(of entry: LibraryEntry) -> String {
        let n = entry.item.name.lowercased()
        let words = Set(n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if n.contains("opening") || words.contains(where: { $0.hasPrefix("ncop") || $0.range(of: #"^op\d*$"#, options: .regularExpression) != nil }) {
            return "Openings"
        }
        if n.contains("ending") || words.contains(where: { $0.hasPrefix("nced") || $0.range(of: #"^ed\d*$"#, options: .regularExpression) != nil }) {
            return "Endings"
        }
        if n.contains("special") || n.contains("ova") || words.contains(where: { $0.range(of: #"^sp\d+$"#, options: .regularExpression) != nil }) {
            return "Specials"
        }
        switch (entry.item.extraType ?? "").lowercased() {
        case "trailer": return "Trailers"
        case "featurette", "short": return "Featurettes"
        case "behindthescenes": return "Behind the Scenes"
        case "deletedscene": return "Deleted Scenes"
        case "interview": return "Interviews"
        default: return "Extras"
        }
    }

    /// "ACCA 13-Territory Inspection Dept. - SP04" → "Special 4".
    public static func name(of entry: LibraryEntry, showName: String) -> String {
        var name = entry.item.name
        // The show's own name at the front, and the separator after it.
        let bare = SearchKey.normalize(showName)
        if let dash = name.range(of: " - "),
           SearchKey.normalize(String(name[..<dash.lowerBound])).hasPrefix(bare.prefix(max(4, bare.count / 2))) {
            name = String(name[dash.upperBound...])
        }
        let rewrites: [(String, String)] = [
            (#"(?i)^NCOP\s*0*(\d+)$"#, "Opening $1"), (#"(?i)^NCED\s*0*(\d+)$"#, "Ending $1"),
            (#"(?i)^OP\s*0*(\d+)$"#, "Opening $1"), (#"(?i)^ED\s*0*(\d+)$"#, "Ending $1"),
            (#"(?i)^SP\s*0*(\d+)$"#, "Special $1"),
        ]
        for (pattern, template) in rewrites {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(name.startIndex..., in: name)
                if regex.firstMatch(in: name, range: range) != nil {
                    return regex.stringByReplacingMatches(in: name, range: range, withTemplate: template)
                }
            }
        }
        return name
    }
}
