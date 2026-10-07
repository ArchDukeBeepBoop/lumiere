import Foundation

/// How subtitles are drawn: a font, a size, and the outline that keeps them
/// readable over a bright frame.
///
/// Streaming services each settled on a look, and they are recognisable enough that
/// matching one is a real preference rather than a novelty: a heavy condensed face
/// with a hard outline reads very differently from a rounded one with a soft shadow.
/// The typefaces themselves are licensed and are not shipped here — these presets
/// use the fonts vendored in the bundle, which were chosen to sit close to each
/// house style without being it.
///
/// Applies only to *plain* subtitle formats — SRT, VTT, plain PGS text. An ASS or
/// SSA track carries its own styling, and overriding it would throw away the
/// positioning and colour a fansub group wrote deliberately. That is the difference
/// between a signs track that lands on the sign and one that sits over someone's
/// face, so the choice is honoured rather than replaced.
public struct SubtitleStyle: Sendable, Identifiable, Equatable {

    public let id: String
    public let title: String
    /// The family name libass resolves, which must match a font in the bundle or on
    /// the system — and must match it *exactly*, trailing spaces included.
    ///
    /// A name libass cannot find does not fail: fontconfig returns its closest
    /// guess, so the subtitle renders in a face nobody chose and the setting looks
    /// as though it half-worked. Check a new entry by rendering it —
    /// `mpv --sub-fonts-dir=<dir> --sub-font="<family>"` — against a deliberately
    /// absent name, and confirm the two differ.
    public let fontFamily: String
    /// As a percentage of the video height, so a subtitle is the same relative size
    /// on a 720p file and a 4K one.
    public let sizePercent: Double
    public let outlineWidth: Double
    public let shadowOffset: Double
    /// Where the bottom of the text sits, in the same relative terms.
    public let marginPercent: Double
    public let detail: String

    /// Where mpv puts a subtitle when nobody overrides it: `sub-margin-y=34`,
    /// expressed in this type's percentage.
    ///
    /// Every preset but Broadcast uses it. They used to each pick their own number
    /// — 20, 26, 30 — all of them *below* the player's own position, so choosing any
    /// preset quietly dropped the subtitle closer to the bottom edge than the player
    /// would have put it, and nothing said so. A house style is a font and a weight
    /// and an outline; where the line sits is the player's business.
    public static let defaultMarginPercent = 34.0 / 5

    public static let all: [SubtitleStyle] = [
        SubtitleStyle(
            id: "default",
            title: "Player Default",
            // mpv's own numbers, stated rather than assumed. Queried from the
            // binary: sub-font-size 38, sub-outline-size 1.65, sub-shadow-offset 0,
            // sub-margin-y 34. Divided back through this type's percentages, which
            // is what makes them survive a window resize.
            fontFamily: "Helvetica Neue",
            sizePercent: 38.0 / 11,
            outlineWidth: 1.65,
            shadowOffset: 0,
            marginPercent: defaultMarginPercent,
            detail: "mpv's own look: a plain grotesque with a thin black outline "
                  + "and no shadow."
        ),
        SubtitleStyle(
            id: "broadcast",
            title: "Broadcast",
            // No outline at all, which is the whole character of it: a soft shadow
            // carries the text off the picture instead of a hard black edge, and it
            // sits higher up the frame than the others.
            fontFamily: "Arial Rounded MT Bold",
            sizePercent: 4.8,
            outlineWidth: 0,
            shadowOffset: 1.8,
            marginPercent: 10.0,
            detail: "Rounded and unoutlined, lifted clear of the bottom edge — the "
                  + "look broadcast captions and the streaming players settled on. "
                  + "Gentler on a dark frame, weaker over a bright one."
        ),
        SubtitleStyle(
            id: "streaming",
            title: "Streaming",
            // The trailing space is not a typo — it is the family name the font
            // file actually declares, and libass matches on that. Asking for
            // "Netflix Sans" without it does not fail loudly: fontconfig
            // fuzzy-matches to some other face and renders happily in the wrong
            // font. Verified by rendering both through mpv against this same
            // fonts directory; they produce different pixels, and neither is the
            // no-such-font fallback.
            fontFamily: "Netflix Sans ",
            sizePercent: 4.6,
            outlineWidth: 1.6,
            shadowOffset: 1.2,
            marginPercent: defaultMarginPercent,
            detail: "Even weight, generous spacing, a soft drop shadow rather than a "
                  + "hard outline. Calm on live action, less so over busy animation."
        ),
        SubtitleStyle(
            id: "simulcast",
            title: "Simulcast",
            fontFamily: "Asap Condensed",
            sizePercent: 5.2,
            outlineWidth: 2.4,
            shadowOffset: 0.4,
            marginPercent: defaultMarginPercent,
            detail: "Condensed and bold with a hard black outline — the look most "
                  + "simulcast anime ships with. Long lines fit without shrinking."
        ),
        SubtitleStyle(
            id: "fansub",
            title: "Fansub",
            fontFamily: "Fontnimation",
            sizePercent: 5.4,
            outlineWidth: 2.8,
            shadowOffset: 0.0,
            marginPercent: defaultMarginPercent,
            detail: "Heavier still, outline only and no shadow. What most fansub "
                  + "scripts were typeset against."
        ),
    ]

    public init(
        id: String,
        title: String,
        fontFamily: String,
        sizePercent: Double,
        outlineWidth: Double,
        shadowOffset: Double,
        marginPercent: Double,
        detail: String = ""
    ) {
        self.id = id
        self.title = title
        self.fontFamily = fontFamily
        self.sizePercent = sizePercent
        self.outlineWidth = outlineWidth
        self.shadowOffset = shadowOffset
        self.marginPercent = marginPercent
        self.detail = detail
    }

    public static func style(id: String?) -> SubtitleStyle {
        all.first { $0.id == id } ?? all[0]
    }

    /// The mpv options this style sets.
    ///
    /// `sub-ass-override=no` is the load-bearing one: it tells libass to leave an
    /// ASS track's own styling alone, so these settings reach SRT and VTT without
    /// flattening a typeset script. Returning the options rather than applying them
    /// keeps this testable and keeps the engine free of preset knowledge.
    public var mpvOptions: [(String, String)] {
        // No early return for `default` any more, and that is the fix for "the
        // player default doesn't look like mpv".
        //
        // It used to set `sub-ass-override` and nothing else, leaving the font to
        // mpv's own `sans-serif` — which is not a font but a request, answered
        // differently depending on who answers it. The app bundles *both*
        // fontconfig and CoreText and libass picks whichever it finds, so the same
        // preset drew a different typeface in the app than in mpv on the same
        // machine, at the same version, on the same file. A preset whose result
        // depends on which font provider won is not a preset.
        //
        // Every value is stated now, including this one's, which are mpv's own
        // documented defaults.
        [
            // Ahead of everything else, because it decides whether any of it
            // applies: `no` leaves an ASS or SSA script entirely alone. See the
            // type's own documentation — this is deliberate, not an oversight, and
            // it is *not* mpv's default (`scale`).
            ("sub-ass-override", "no"),
            ("sub-font", fontFamily),
            ("sub-font-size", String(format: "%.1f", sizePercent * 11)),
            // `sub-border-size` is an alias for `sub-outline-size` in current mpv;
            // the alias is used so this keeps working on the older libmpv the
            // bundle may be built against.
            ("sub-border-size", String(format: "%.2f", outlineWidth)),
            ("sub-shadow-offset", String(format: "%.1f", shadowOffset)),
            ("sub-margin-y", String(Int(marginPercent * 5))),
            ("sub-color", "#FFFFFFFF"),
            ("sub-border-color", "#FF000000"),
            ("sub-bold", id == "simulcast" || id == "fansub" ? "yes" : "no"),
        ]
    }
}
