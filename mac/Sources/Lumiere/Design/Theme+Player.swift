import SwiftUI
import LumiereKit

/// The player's own tokens.
///
/// Separate from Theme.swift because chrome drawn over video answers to different
/// rules than the rest of the app. The surface underneath is a moving picture on
/// black rather than a page, so nothing here resolves against the appearance —
/// exactly the reasoning behind `Palette.onArtwork`. And the pointer crossing a
/// darkened film needs bigger targets than a dense list does, so the sizes are
/// their own family rather than the control sizes used everywhere else.
///
/// Additive: nothing in this file changes a value Home or Detail already reads.
public extension Theme {

    /// Colour for chrome over video.
    enum PlayerPalette {

        // MARK: Surfaces

        /// The transport bar and the floating panels, as a wash rather than a flat
        /// fill: a slab with a lighter top edge reads as a physical control surface,
        /// where a single opacity reads as a rectangle someone forgot to style.
        public static let surfaceTop = Color.black.opacity(0.52)
        public static let surfaceBottom = Color.black.opacity(0.68)
        /// The hairline that separates the slab from the picture. Without it the
        /// bar has no edge at all over a dark scene.
        public static let surfaceStroke = Color.white.opacity(0.13)
        public static let surfaceShadow = Color.black.opacity(0.5)

        /// The wash under the title and under the transport.
        ///
        /// Chrome over a bright scene — snow, a white wall, daylight — is otherwise
        /// unreadable no matter how the bar itself is styled, because the text
        /// outside the bar has nothing behind it.
        public static let scrimTop = Color.black.opacity(0.55)
        public static let scrimBottom = Color.black.opacity(0.72)

        // MARK: Scrub bar

        /// The three bands have to be told apart at a glance while a picture moves
        /// behind them, so the steps between them are wide rather than tasteful.
        public static let scrubTrack = Color.white.opacity(0.20)
        public static let scrubBuffered = Color.white.opacity(0.42)
        /// Played. The dark-appearance gold, fixed rather than `Palette.accent`:
        /// that token resolves to a much darker gold in light appearance, which is
        /// right on a white page and nearly invisible on a black scrub track.
        public static let scrubPlayed = Color(hex: 0xC9A227)
        public static let handle = Color.white
        public static let handleShadow = Color.black.opacity(0.55)
        /// A chapter mark. Dark rather than light so one mark reads the same
        /// whether it happens to sit on the played gold or the unplayed track —
        /// two colours for one kind of thing is what made them read as artefacts.
        public static let chapterMark = Color.black.opacity(0.62)

        // MARK: Controls

        /// The plate under a hovered secondary control. Drawn only while hovered,
        /// so a row of eight icons is eight glyphs rather than eight buttons.
        public static let controlHover = Color.white.opacity(0.16)
        /// A secondary control that is currently doing something — the tracks
        /// button while its panel is open.
        public static let controlActive = Color.white.opacity(0.22)

        /// The one primary. An inverted disc rather than another glyph, because
        /// "which of these is play" should not need reading: on chrome this dark
        /// a filled white circle is the only thing on the bar with weight.
        public static let primaryFill = Color.white
        public static let primaryGlyph = Color.black

        /// A menu row under the pointer.
        public static let rowHover = Color.white.opacity(0.10)
        public static let rowSelected = Color.white.opacity(0.06)
    }

    /// Fixed sizes for the transport. Points, all of them.
    enum PlayerMetric {
        /// The gap between the bar and the bottom of the window.
        public static let barInset: CGFloat = 28

        public static let primaryButton: CGFloat = 54
        public static let primaryGlyph: CGFloat = 21
        /// Everything that is not play. A 38pt target with a 16pt glyph is a
        /// comfortable click at arm's length and still visibly subordinate.
        public static let secondaryButton: CGFloat = 38
        public static let secondaryGlyph: CGFloat = 16
        public static let closeButton: CGFloat = 34

        /// The scrub track, idle and while it is being used. It grows under the
        /// pointer, which is both the Apple TV behaviour and what tells you the
        /// thin line is something you may grab.
        public static let scrubHeight: CGFloat = 6
        public static let scrubHeightActive: CGFloat = 9
        /// The invisible band the drag gesture actually covers. A 6pt bar is a 6pt
        /// target, which is not a target.
        public static let scrubHitHeight: CGFloat = 24
        public static let handle: CGFloat = 12
        public static let handleActive: CGFloat = 19
        public static let chapterMarkWidth: CGFloat = 2

        public static let volumeWidth: CGFloat = 96
        public static let volumeTrackHeight: CGFloat = 4
        public static let volumeHandle: CGFloat = 10

        /// The trickplay card. Wider than the 176 it was, because it is now a card
        /// with a timecode rather than a thumbnail with a chip under it.
        public static let trickplayWidth: CGFloat = 208
        /// Paused, the preview is the thing being looked at — larger, as on
        /// Apple TV when you scrub with the picture stopped.
        public static let trickplayWidthPaused: CGFloat = 400
        public static func trickplayWidth(playing: Bool) -> CGFloat { playing ? trickplayWidth : trickplayWidthPaused }
        /// How far the card floats above the scrub bar.
        public static let trickplayLift: CGFloat = 14

        /// The width of the card when it holds only a timecode.
        ///
        /// Fixed rather than intrinsic so the label stays centred on the pointer as
        /// the digits change — `1:02:03` and `59:59` are different widths, and a
        /// card that resizes under the cursor reads as one that is not following it.
        /// Wide enough for `1:02:03` with the card's own padding.
        public static let timecodeCardWidth: CGFloat = 84

        /// The tracks panel. Wide enough for its four tab labels on one line —
        /// Audio, Subtitles, Speed, Chapters — which is what sets the number: a
        /// tab strip that wraps stops reading as a tab strip.
        /// How wide the Skip / Next Episode pill may grow before its label
        /// truncates. Generous, because the episode title is the whole point of
        /// the offer, and bounded, because it is drawn over the picture.
        public static let promptMaxWidth: CGFloat = 460

        public static let panelWidth: CGFloat = 344
        public static let panelMaxHeight: CGFloat = 320

        /// The tracks panel, sized to the player rather than to a constant.
        ///
        /// A fixed 344 × 320 is right in a small window and wrong in fullscreen: at
        /// 1512pt wide it is a fifth of the picture, and the Up Next list inside it
        /// wrapped every episode title onto three lines. These take a share of the
        /// player and clamp, so the panel grows with the room it has and never
        /// outgrows a window smaller than the constant it started from.
        public static func panelWidth(in size: CGSize) -> CGFloat {
            guard size.width > 0 else { return panelWidth }
            return min(max(panelWidth, size.width * 0.28), 520)
        }

        /// The settings panel. The arithmetic — and the reasoning — is in
        /// `PlayerPanelSize`, where it can be tested against window sizes this
        /// machine does not have.
        public static func settingsPanelSize(in size: CGSize) -> CGSize {
            PlayerPanelSize.settingsPanel(in: size)
        }

        /// One row of a player panel: a line of text with its own padding.
        ///
        /// Not measured at runtime — the rows are uniform by construction, so the
        /// arithmetic below can say how many of them fit rather than hoping.
        public static let panelRowHeight: CGFloat = 34

        /// How many rows the tracks panel aims to show without scrolling.
        public static let panelTargetRows: CGFloat = 8

        /// How many episodes the Up Next list aims to show without scrolling.
        ///
        /// A season is the unit here. Four episodes makes the list a keyhole onto
        /// the thing it exists to present; fourteen covers most seasons at a glance.
        public static let queueTargetRows: CGFloat = 14

        /// Room left above a panel so it never reaches the title bar.
        public static let panelTopMargin: CGFloat = 96

        /// How tall a panel's list may grow, given the player it is drawn over.
        ///
        /// The number never used to matter. The panel was an `.overlay` on the
        /// transport bar, and an overlay is proposed its parent's size — so however
        /// large this returned, the list could not be taller than the bar it hung
        /// off, which is why Up Next showed two episodes. It is drawn over the
        /// player now, and this is a real bound rather than a wish.
        ///
        /// `rows` is the floor: the panel is at least that many rows tall wherever
        /// there is room for them, and otherwise takes what the window has.
        public static func panelMaxHeight(
            in size: CGSize, rows: CGFloat = panelTargetRows
        ) -> CGFloat {
            let wanted = rows * panelRowHeight
            guard size.height > 0 else { return wanted }
            // What is actually free: the picture, less the transport bar below the
            // panel and a margin above it.
            let room = size.height - promptLift - panelTopMargin
            return max(160, min(max(wanted, room), 760))
        }

        /// How far the scrims reach in from the top and bottom edges.
        public static let scrimHeight: CGFloat = 200
        /// How far the chrome travels as it fades. Small on purpose — chrome that
        /// slides a long way reads as a sheet arriving rather than controls waking.
        public static let chromeSlide: CGFloat = 14

        /// Where the title block starts vertically.
        ///
        /// Below the traffic lights, which stay on screen during playback (see
        /// `WindowChrome`) and sit in the top ~28pt of the window. A title at the
        /// usual inset lands on top of them.
        public static let titleTopInset: CGFloat = 44
        /// The logo in the title bar. Smaller than the hero's: it names what is
        /// playing rather than selling it, and sits over a picture in motion.
        public static let titleLogoWidth: CGFloat = 220
        public static let titleLogoHeight: CGFloat = 64
        /// Same problem, other corner: the statistics HUD would otherwise open
        /// under the Close button.
        public static let hudTopInset: CGFloat = 88

        /// How far the Skip / Next Episode pill sits from the right edge.
        ///
        /// Tighter than the page's 40pt margin. This is chrome over a picture, not
        /// type in a column, and the further in it sits the more of the frame it
        /// covers — so it goes to the edge and stays out of the way.
        public static let promptInset: CGFloat = 20

        /// The transport bar's real height, summed from its own parts rather than
        /// guessed: bottom inset, padding, the play button, the gap, the scrub hit
        /// area, top padding. 146pt as these stand.
        public static let barHeight: CGFloat =
            barInset + Theme.Space.md + primaryButton
            + Theme.Space.md + scrubHitHeight + Theme.Space.lg

        /// How far the skip / next-episode prompt sits above the bottom edge.
        ///
        /// The bottom-right corner, as low as it can go without ever touching the
        /// transport bar — and a single fixed value rather than one height with the
        /// chrome up and another with it down. That switch is what made the button
        /// dodge the pointer: the bar appears the moment you move the mouse, so the
        /// prompt rose away exactly as you reached for it.
        ///
        /// Derived from `barHeight` so it cannot drift if the bar is restyled. The
        /// 10pt is the visible gap between the two.
        public static let promptLift: CGFloat = barHeight + 10

        /// The handle's own shadow. Tight, because it exists to keep a white dot
        /// visible over a white scene rather than to lift it off the bar.
        public static let handleShadow: CGFloat = 3
        public static let handleShadowY: CGFloat = 1

        public static let surfaceShadow: CGFloat = 24
        public static let surfaceShadowY: CGFloat = 10
    }
}

// MARK: - Additions to the shared scales

public extension Theme.Radius {
    /// The transport bar. `pill` (12) was drawn for a 60pt-high slab; the bar is
    /// now half again as tall, and corner radius is not scale-free — the same
    /// reasoning as `posterLarge`.
    static let playerBar: CGFloat = 20
    /// A floating player panel: the tracks list, the trickplay card.
    static let playerPanel: CGFloat = 14
    static let trickplay: CGFloat = 10
}

public extension Theme.Font {
    /// What is playing, over the picture. Quiet for a 40pt page title but firm
    /// enough to be the identity of the film rather than a caption — the old 12pt
    /// `cardTitle` here was a tooltip.
    static let playerTitle = SwiftUI.Font.system(size: 21, weight: .semibold)
    /// The show, season and episode line beneath it.
    static let playerSubtitle = SwiftUI.Font.system(size: 14, weight: .medium)
    /// The scrubber's elapsed and remaining. `timecode` (11) is a HUD field read
    /// while leaning in; this one is read at a glance mid-film.
    static let playerTimecode = SwiftUI.Font.system(size: 13, weight: .medium, design: .monospaced)
    static let playerTab = SwiftUI.Font.system(size: 12, weight: .semibold)
    static let playerRow = SwiftUI.Font.system(size: 13, weight: .regular)
    static let trickplayTimecode = SwiftUI.Font.system(size: 12, weight: .semibold, design: .monospaced)
}

public extension Theme.Motion {
    /// Chrome coming back.
    ///
    /// Faster than it leaves, and that asymmetry is the whole trick: controls you
    /// asked for should already be there, and controls you stopped using should
    /// drift out rather than blink off. `chrome` stays the outgoing curve.
    static let chromeReveal = Animation.easeOut(duration: base)
}
