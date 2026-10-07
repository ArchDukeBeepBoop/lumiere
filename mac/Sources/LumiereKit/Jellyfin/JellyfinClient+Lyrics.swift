import Foundation

/// One line of lyrics; `start` in seconds when the lyrics are synced.
public struct LyricLine: Sendable, Equatable, Identifiable {
    public let id: Int
    public let text: String
    public let start: Double?

    public init(id: Int, text: String, start: Double?) {
        self.id = id
        self.text = text
        self.start = start
    }

    /// The line playing at `position`: the last one that has started. Nil
    /// before the first, or for unsynced lyrics.
    public static func current(in lines: [LyricLine], at position: Double) -> Int? {
        var found: Int?
        for line in lines {
            guard let start = line.start else { return nil }
            if start > position { break }
            found = line.id
        }
        return found
    }

    /// Back to LRC text, so editing synced lyrics keeps their timing.
    public static func lrc(_ lines: [LyricLine]) -> String {
        lines.map { line in
            guard let start = line.start else { return line.text }
            let minutes = Int(start) / 60
            return String(format: "[%02d:%05.2f]", minutes, start - Double(minutes * 60)) + line.text
        }.joined(separator: "\n")
    }
}

public extension JellyfinClient {
    /// A track's lyrics as lines, timed where the server has them synced.
    /// Nil when there are none, or the server has no lyrics support.
    func lyricLines(itemId: String) async -> [LyricLine]? {
        guard let data = try? await sendData(path: "Audio/\(itemId)/Lyrics"),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let text = object["Lyrics"] as? String {
            let lines = text.components(separatedBy: .newlines)
            return lines.enumerated().map { LyricLine(id: $0.offset, text: $0.element, start: nil) }
        }
        guard let raw = object["Lyrics"] as? [[String: Any]], !raw.isEmpty else { return nil }
        return raw.enumerated().map { index, line in
            let ticks = (line["Start"] as? NSNumber)?.doubleValue
            return LyricLine(id: index, text: line["Text"] as? String ?? "",
                             start: ticks.map { $0 / 10_000_000 })
        }
    }
}
