import Foundation

/// How a 0–10 community rating is written, everywhere it is written.
///
/// One figure, no decimal point. `8.6` reads as a measurement — as though the
/// difference between 8.6 and 8.7 meant something — when the number underneath
/// is a rolling average of strangers' votes that moves on its own overnight. A
/// whole number claims exactly what the data supports: this is an eight.
///
/// Shared rather than formatted at each site because it was formatted at each
/// site: three of them with `String(format: "%.1f")`, including the home hero's
/// one line of editorial argument, which read "Rated 10.0, and you have never
/// opened it" — false precision in the sentence meant to sound like a person.
public enum Rating {

    /// Nil in, nil out, so a caller can append this to a list of parts without
    /// deciding separately whether there is a rating to show.
    public static func text(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        // A switch, because "one figure" is a taste. See `Preference`.
        guard Preference.roundsRatings.value else {
            return String(format: "%.1f", value)
        }
        return String(Int(value.rounded()))
    }

    /// With the star, for the metadata lines that carry one.
    public static func starred(_ value: Double?) -> String? {
        guard let text = text(value) else { return nil }
        return "★ \(text)"
    }
}
