import SwiftUI
import LumiereKit
import AppKit

/// The single source of truth for every colour, radius, spacing step and duration
/// in Lumiere. Views consume these tokens; nothing hardcodes a hex value or a
/// magic number. If a value appears twice in a view file, it belongs here instead.
///
/// Every colour is a *semantic* token that resolves against the current system
/// appearance. A view never asks "is it dark?" — it asks for `textPrimary` and
/// gets the right answer in both. That is the only way an app this colour-heavy
/// stays consistent across two appearances.
public enum Theme {

    // MARK: - Colour

    public enum Palette {
        /// Window background. Apple TV's grey in dark — the system greys, untinted,
        /// from #1C1C1E up through the surfaces — rather than the near-black it
        /// was; plain white in light, as every macOS content area is.
        public static let canvas = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
        /// Sidebar and toolbar chrome.
        public static let chrome = Color.dynamic(light: 0xF2F2F4, dark: 0x232325)
        /// Cards, rows, inline panels sitting on the canvas.
        public static let surface = Color.dynamic(light: 0xF5F5F7, dark: 0x2C2C2E)
        /// Selected rows, hovered cards, popovers.
        public static let surfaceRaised = Color.dynamic(light: 0xE9E9EE, dark: 0x3A3A3C)

        public static let border = Color.dynamic(light: 0xD9D9DE, dark: 0x38383A)
        /// The outline on tiles, pills and round buttons: none in dark, as on
        /// Apple TV, where surfaces part by tone alone; kept in light, where
        /// white on white needs an edge.
        public static let hairline = Color.dynamic(light: 0xD9D9DE, dark: 0x38383A, darkOpacity: 0)
        public static let borderStrong = Color.dynamic(light: 0xB6B6BE, dark: 0x48484A)

        public static let textPrimary = Color.dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
        public static let textSecondary = Color.dynamic(light: 0x5C5C63, dark: 0xAEAEB2)
        public static let textMuted = Color.dynamic(light: 0x86868C, dark: 0x8E8E93)
        public static let textDisabled = Color.dynamic(light: 0xB0B0B8, dark: 0x5A5A5E)

        /// Warm gold. Used for progress, focus, and exactly one primary action per
        /// screen — never as a decorative fill.
        ///
        /// The light value is deliberately darker: the dark-mode gold on white is
        /// about 2:1 against text, which fails legibility outright.
        public static let accent = Color.dynamic(light: 0x8A6E12, dark: 0xC9A227)
        public static let accentMuted = Color.dynamic(light: 0xE2D3A0, dark: 0x5C4F28)
        /// Text and glyphs drawn *on* an accent fill.
        public static let onAccent = Color.dynamic(light: 0xFFFFFF, dark: 0x0D0F12)

        /// Badge families for the technical chips (4K DV, TrueHD 7.1, Direct play).
        /// Colour carries meaning: video gold, audio green, playback route blue.
        public static let badgeVideo = Color.dynamic(light: 0x715A0F, dark: 0xE8D59A)
        public static let badgeVideoBorder = Color.dynamic(light: 0xD8C68C, dark: 0x5C4F28)
        public static let badgeAudio = Color.dynamic(light: 0x1B6349, dark: 0x9FD8C4)
        public static let badgeAudioBorder = Color.dynamic(light: 0x9CD2BD, dark: 0x2A5044)
        public static let badgeStream = Color.dynamic(light: 0x1A5486, dark: 0x9FC2E8)
        public static let badgeStreamBorder = Color.dynamic(light: 0xA3C6E6, dark: 0x294159)
        public static let badgeNeutral = Color.dynamic(light: 0x5C5C63, dark: 0xA8B0BC)
        public static let badgeNeutralBorder = Color.dynamic(light: 0xC7C7CE, dark: 0x39414D)

        public static let danger = Color.dynamic(light: 0xBE2F2C, dark: 0xE24B4A)
        public static let success = Color.dynamic(light: 0x1C8560, dark: 0x5DCAA5)

        /// The primary Play action.
        ///
        /// Untinted rather than gold, matching Infuse: over artwork a neutral pill
        /// reads as the one thing to press, where a tinted one competes with
        /// whatever is behind it.
        ///
        /// It inverts between appearances rather than staying white. Infuse's Play
        /// sits high on the backdrop where white has something to contrast with;
        /// Lumiere's sits lower, where the backdrop has already faded to the page,
        /// and a white pill on a white page is invisible.
        public static let playButton = Color.dynamic(light: 0x1D1D1F, dark: 0xF2F4F7)
        public static let playButtonLabel = Color.dynamic(light: 0xFFFFFF, dark: 0x0D0F12)

        /// Unwatched marker. Infuse uses an orange corner triangle, and it reads
        /// in both appearances without adjustment.
        public static let unwatched = Color.dynamic(light: 0xF07B22, dark: 0xF08A2E)

        /// Scrims drawn on top of artwork — a progress track on a poster, a play
        /// affordance on a still. Always dark in both appearances, because they
        /// sit on a photograph rather than on the page.
        public static let onArtwork = Color.black.opacity(0.55)
        public static let onArtworkStrong = Color.black.opacity(0.62)
        /// The foot of a scrim laid over poster art, where a label has to win
        /// against the poster's own printed title.
        public static let onArtworkOpaque = Color.black.opacity(0.88)

        /// Text set *over* artwork — a genre name on its card. White in both
        /// appearances for the same reason as the scrims above: the surface under
        /// it is a photograph, not the page, and a light-mode `textPrimary` here
        /// would be near-black on a darkened still.
        /// The ground under artwork that has text drawn on it.
        ///
        /// Fixed rather than `dynamic`, and that is the point. `surface` is
        /// `#F2F2F5` in light mode, so whenever a backdrop failed to load — offline,
        /// mid-download, or on a title the server has no art for — the white
        /// on-artwork type landed on near-white and vanished. The picture is a
        /// photograph in both appearances and the text over it is white in both, so
        /// what stands in for a missing picture has to be dark in both too.
        public static let artworkPlaceholder = Color(nsColor: NSColor(name: nil) { _ in
            // Dark in both, for the white type over it — but warm on Paper,
            // where a cool grey block stands out on the page.
            PaperTheme.isOn ? NSColor(hex: 0x3A3128) : NSColor(hex: 0x14171B)
        })

        public static let onArtworkText = Color.white
        /// The accent where it sits on artwork, which is dark in every theme:
        /// the standard gold, always. Paper's oxblood is an ink for pale
        /// stock and all but vanished on a hero's dark gradient.
        public static let accentOnArtwork = Color(hex: 0xC9A227)
        public static let onArtworkTextMuted = Color.white.opacity(0.78)

        /// The shadow a card casts while it is hovered.
        ///
        /// Deeper in dark than in light, which is the opposite of the usual
        /// instinct: on a near-black canvas a 0.18 shadow is invisible, so the
        /// lift has to come from a much darker halo to read at all.
        public static let cardShadow = Color.dynamic(
            light: 0x000000, dark: 0x000000, lightOpacity: 0.18, darkOpacity: 0.55
        )

        /// Chrome drawn over video. Always dark — video is always on black,
        /// regardless of the app's appearance.
        public static let playerChrome = Color.black.opacity(0.62)
        public static let onPlayerChrome = Color.white
        public static let onPlayerChromeSecondary = Color.white.opacity(0.72)
    }

    // MARK: - Spacing

    /// A 4pt base grid. Every gap, inset and pad is one of these.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48

        /// The gap between two shelves. Off the 4pt grid's named steps on purpose:
        /// `xxl` reads as one continuous wall of artwork once a home screen has a
        /// dozen rows, and `xxxl` pushes the second shelf off a laptop screen.
        public static let shelfGap: CGFloat = 40

        /// The gap between two tiles inside a shelf.
        ///
        /// `lg` was drawn for 140pt posters. At the Apple TV sizes below, a 16pt
        /// gutter between two 200pt cards reads as a seam rather than a gap — the
        /// tiles look like one strip of artwork instead of a row of things you can
        /// pick between. The gutter has to grow with the tile.
        public static let tileGap: CGFloat = 20

        /// The left edge every home row starts at — titles, filter bar and first
        /// tile alike.
        ///
        /// Wider than `xxl` because the tiles got wider: Apple TV's rows sit well
        /// in from the window edge, and at 32pt a 200pt poster looked pinned to it.
        /// One token rather than `xxl` at each call site so the header, the tiles
        /// and the filter above them can never drift out of alignment.
        public static let shelfInset: CGFloat = 40
    }

    // MARK: - Radius

    public enum Radius {
        public static let badge: CGFloat = 4
        /// Measured against Infuse: at a ~140pt poster its corners are visibly
        /// rounder than 6pt read.
        public static let poster: CGFloat = 8
        /// The corner of a large tile — a home shelf poster, a continue card, a
        /// genre card.
        ///
        /// Corner radius is not scale-free: 8pt on a 200pt-wide poster is a
        /// proportionally *sharper* corner than 8pt on a 140pt one, so keeping the
        /// old value while doubling the tile area would have quietly squared the
        /// artwork off. Apple TV's own cards sit around 10–12 at these sizes.
        public static let posterLarge: CGFloat = 12
        public static let control: CGFloat = 6
        /// A large action pill — a detail page's Play button. `control` (6) is
        /// drawn for a 28pt-high menu button; under a 52pt one it reads as a
        /// square slab, for the same reason `posterLarge` exists.
        public static let playControl: CGFloat = 10
        public static let card: CGFloat = 10
        public static let panel: CGFloat = 14
        /// The player's floating control bar.
        public static let pill: CGFloat = 12
    }

    // MARK: - Typography

    /// SF Pro throughout. Sizes are fixed rather than dynamic-type driven because
    /// this is a 10-foot-adjacent media UI where layout density is the point.
    /// The scale's numbers. Defined in `TypeScale`, in the kit, so the steps
    /// between them can be tested; `Font` below builds the faces from these.
    public typealias Size = TypeScale

    public enum Font {
        public static let hero = SwiftUI.Font.system(size: TypeScale.hero, weight: .bold)
        public static let title = SwiftUI.Font.system(size: TypeScale.title, weight: .bold)
        /// A heading inside a panel. 15 against a 14 body was half a step; a
        /// heading that does not announce itself is a heading nobody reads.
        public static let sectionHeader = SwiftUI.Font.system(size: TypeScale.sectionHeader, weight: .semibold)
        /// The title above a shelf. Larger than `sectionHeader`, which is a label
        /// inside a panel: a shelf title has to hold its own against a row of
        /// artwork underneath it, and at 15pt it did not.
        public static let shelfHeader = SwiftUI.Font.system(size: TypeScale.shelfHeader, weight: .bold)
        /// A home shelf's own title.
        ///
        /// Bold and large enough to be a piece of the shelf rather than a caption
        /// floating above it — which is what 19pt semibold became once the tiles
        /// underneath grew to 200pt. Apple TV's row headings are the second-loudest
        /// thing on its home screen after the artwork, and this is that size.
        public static let shelfTitle = SwiftUI.Font.system(size: 26, weight: .bold)
        /// Running text, one step up from where it was.
        ///
        /// The scale had body 13, card title 12 and caption 11 — three levels
        /// inside two points, which read as one level however they were
        /// weighted. Contrast is the whole discipline here, so the three now sit
        /// 14 / 12 / 11 with weight doing the rest: a card title is *medium* at
        /// 12 under a poster that names itself, and a caption is quiet at 11.
        public static let body = SwiftUI.Font.system(size: TypeScale.body, weight: .regular)
        public static let cardTitle = SwiftUI.Font.system(size: TypeScale.cardTitle, weight: .medium)
        /// The title under a large tile. 12pt reads as a caption below a 200pt
        /// poster; the label has to scale with the thing it labels.
        public static let cardTitleLarge = SwiftUI.Font.system(size: 15, weight: .medium)
        /// A genre card's name, set over its artwork.
        public static let genreTitle = SwiftUI.Font.system(size: 24, weight: .bold)
        /// A library card's name, set over its artwork. Bold like `genreTitle` —
        /// it is the label the card exists to carry — but smaller, because the
        /// card is 180pt rather than 300pt wide and names like "Anime Movies"
        /// have to fit in two lines without shrinking.
        public static let libraryTitle = SwiftUI.Font.system(size: 17, weight: .bold)
        /// Deliberately not raised with the rest. The gap between body and
        /// caption is what makes a caption *quiet*, and closing it was half the
        /// problem — this stays at 11 while body moves to 14.
        public static let caption = SwiftUI.Font.system(size: TypeScale.caption, weight: .regular)
        /// The second line under a large tile, paired with `cardTitleLarge`.
        public static let captionLarge = SwiftUI.Font.system(size: 13, weight: .regular)
        public static let badge = SwiftUI.Font.system(size: 10, weight: .medium)
        public static let timecode = SwiftUI.Font.system(size: 11, design: .monospaced)
        /// The label on a detail page's Play/Resume pill. `cardTitle` (12) is a
        /// tile caption, and on the one button a whole page is built around it
        /// read as a hyperlink rather than as the thing to press.
        public static let playLabel = SwiftUI.Font.system(size: 17, weight: .semibold)
        /// A detail header's metadata line. One step up from `body` because it
        /// sits directly under 150pt of logo artwork rather than inside a panel.
        public static let detailMeta = SwiftUI.Font.system(size: 15, weight: .medium)
        /// A detail page's title where the server has no logo artwork to stand
        /// in for it. `hero` (34) is sized for the home hero's 460pt band; a
        /// detail backdrop is a full-width 16:9, roughly twice that tall.
        public static let detailTitle = SwiftUI.Font.system(size: 46, weight: .heavy)
    }

    // MARK: - Motion

    /// Short and springless. Infuse's browsing feel comes from restraint — long
    /// or bouncy transitions read as sluggish once you are three levels deep.
    public enum Motion {
        public static let fast: Double = 0.12
        public static let base: Double = 0.20
        public static let slow: Double = 0.32

        public static let hover = Animation.easeOut(duration: fast)
        public static let transition = Animation.easeOut(duration: base)
        public static let chrome = Animation.easeInOut(duration: slow)
    }


}
