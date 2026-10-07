import Foundation

/// What someone typed into Jump to Time, as seconds.
///
/// Accepts the forms people actually type: a timecode (`1:23:45`, `23:45`),
/// units (`1h20m`, `20m`, `90s`), a bare number read as minutes — "go to 45"
/// in a film means minute 45 far more often than second 45 — and a percentage
/// of the length. Nil for anything else, so the dialog can say so rather than
/// jumping somewhere surprising. Pure; clamped to the file when its length is
/// known.
public enum TimeEntry {
    public static func seconds(from text: String, duration: Double) -> Double? {
        let entry = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !entry.isEmpty else { return nil }
        guard let raw = parse(entry, duration: duration), raw >= 0 else { return nil }
        return duration > 0 ? min(raw, max(0, duration - 1)) : raw
    }

    private static func parse(_ entry: String, duration: Double) -> Double? {
        if entry.hasSuffix("%") {
            guard duration > 0, let percent = Double(entry.dropLast()) else { return nil }
            return duration * percent / 100
        }
        if entry.contains(":") {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
            guard (2...3).contains(parts.count), !parts.contains(nil) else { return nil }
            return parts.reduce(0) { $0 * 60 + $1! }
        }
        if let minutes = Double(entry) { return minutes * 60 }
        return units(entry)
    }

    /// `1h20m30s` and any subset, in that order.
    private static func units(_ entry: String) -> Double? {
        var total = 0.0, number = "", seen = false
        for character in entry {
            if character.isNumber || character == "." { number.append(character); continue }
            guard let value = Double(number) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return nil
            }
            number = ""; seen = true
        }
        return seen && number.isEmpty ? total : nil
    }
}
