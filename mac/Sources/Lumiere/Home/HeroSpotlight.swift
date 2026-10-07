import SwiftUI
import LumiereKit

/// The hero, cycling. Apple TV's spotlight: one backdrop at a time, chevrons to
/// move between them, a dot per position.
///
/// Wraps `HeroBackdrop` rather than replacing it — the backdrop still owns the
/// logo, the metadata line, the resume track and the buttons, and both home
/// layouts still draw the same one.
///
/// **Memory.** A hero backdrop is the largest bitmap the app decodes: 16:9 at
/// window width, at screen scale. Cycling could easily mean six of those resident
/// at once, which would undo the whole reason the shelves went lazy. So exactly
/// one is built at a time. The rotation is a single child keyed by item id, and
/// the outgoing one is *removed* from the hierarchy by the cross-fade rather than
/// hidden — which is what lets `RemoteImage.onDisappear` drop its `CGImage`. At
/// rest that is one decoded backdrop, the same as before this change; during a
/// fade it is briefly two, and never more. Nothing is prefetched: paging to a
/// neighbour is a cache hit in `ImagePipeline` if you have been there, and a
/// download if you have not, and neither costs standing memory.
///
/// Cross-fade rather than slide, deliberately. A slide has to have somewhere to
/// slide from, which means the next backdrop must already be decoded and laid out
/// off-screen — the one thing the paragraph above exists to prevent. A fade also
/// suits artwork better: two unrelated film stills sliding past each other reads
/// as a broken scroll view.
struct HeroSpotlight: View {
    let entries: [LibraryEntry]
    let pipeline: ImagePipeline
    let serverURL: URL
    let capabilities: SystemCapabilities
    var onPlay: (String) -> Void = { _ in }
    /// Rotates the whole selection to a different set of titles. Nil where there is
    /// nothing to rotate — the demo library, previews.
    var onRefresh: (() async -> Void)?
    /// item id → why it is being shown. See `SpotlightReason`.
    var reasons: [String: String] = [:]
    @AppStorage(Preference.explainsSpotlight.name) private var explainsSpotlight
        = Preference.explainsSpotlight.defaultValue

    @State private var index = 0
    @AppStorage(Preference.homeShowsBackdrop.name) private var homeBackdrop = Preference.homeShowsBackdrop.defaultValue

    /// Off in Settings: no spotlight at all, and Home opens on its shelves.
    /// Per room, as every setting is.
    private var showsBackdrop: Bool { homeBackdrop }

    /// Clamped rather than trusted. `entries` is reloaded whenever watch state
    /// changes — marking something watched drops it out of the spotlight — and an
    /// index left pointing past the end of a shorter list would crash.
    private var position: Int {
        guard !entries.isEmpty else { return 0 }
        return min(max(0, index), entries.count - 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if !entries.isEmpty, showsBackdrop {
                let entry = entries[position]
                HeroBackdrop(
                    entry: entry,
                    pipeline: pipeline,
                    serverURL: serverURL,
                    capabilities: capabilities,
                    onPlay: onPlay,
                    reason: explainsSpotlight ? reasons[entry.id] : nil
                )
                // Identity is the item, so moving on tears the old backdrop down
                // instead of re-rendering it in place. That teardown is the thing
                // that releases the bitmap.
                .id(entry.id)
                .transition(.opacity)

                if entries.count > 1 {
                    chevrons
                    dots
                }
                refreshButton
            }
        }
        .animation(Theme.Motion.chrome, value: position)
    }

    /// A different set of titles, on demand.
    ///
    /// The rotation used to be tied to launching the app: the pool advanced once at
    /// start-up and held for the session, so seeing anything else meant quitting.
    /// That is a strange thing to ask of someone who just wants a different picture.
    /// Top-trailing, away from the chevrons — those move within this set, this
    /// replaces the set.
    @ViewBuilder
    private var refreshButton: some View {
        if let onRefresh {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    HeroPageButton(icon: "arrow.triangle.2.circlepath", label: "Show different titles") {
                        Task { await onRefresh() }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.lg)
        }
    }

    /// One chevron against each edge, at mid-height.
    ///
    /// Where a carousel's controls belong, and where they could not go before: the
    /// title block used to run from the leading inset out to 620 points with its
    /// vertical centre inside that block, so a left chevron landed on the overview
    /// text. The hero now dissolves into the page across its bottom third and the
    /// text sits inside that dissolved band, which leaves the middle of the frame —
    /// both sides of it — genuinely empty.
    private var chevrons: some View {
        HStack {
            HeroPageButton(icon: "chevron.left", label: "Previous") { step(-1) }
            Spacer(minLength: 0)
            HeroPageButton(icon: "chevron.right", label: "Next") { step(1) }
        }
        .padding(.horizontal, Theme.Space.lg)
        // Centred on the *picture*, not on the whole hero: the bottom third is the
        // title block, and splitting the full height would put the chevrons low
        // enough to sit beside the overview again.
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.bottom, Theme.Art.heroHeight * 0.28)
    }

    /// Bottom-trailing, as one cluster, rather than a chevron pinned to each edge
    /// at mid-height.
    ///
    /// The edge-chevron arrangement is the more familiar carousel shape, but this
    /// hero's title block runs from the leading inset out to 620 points and its
    /// vertical centre is inside that block — a left chevron there lands on top of
    /// the overview text or the Play button. The opposite corner is the one region
    /// of the backdrop that is reliably empty at every window size.
    /// The position dots, kept where they were.
    ///
    /// They stay at the foot rather than joining the chevrons, because they are a
    /// readout and not a control: six small marks at mid-height beside a chevron
    /// read as more buttons, and reaching for one is the mis-click a carousel can
    /// least afford.
    private var dots: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { slot, _ in
                Circle()
                    .fill(
                        slot == position
                            ? Theme.Palette.textPrimary : Theme.Palette.textDisabled
                    )
                    .frame(width: Theme.Art.heroPageDot, height: Theme.Art.heroPageDot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Theme.Space.shelfInset)
        .padding(.vertical, Theme.Space.xxl)
    }

    /// Wraps rather than stopping at the ends. Six items is few enough that a
    /// disabled chevron reads as a bug before it reads as a boundary.
    private func step(_ delta: Int) {
        guard !entries.isEmpty else { return }
        index = (position + delta + entries.count) % entries.count
    }
}

/// One chevron. Its own type only because it needs hover state, which a parent
/// drawing two of them cannot hold.
///
/// Shaped like `QuickLinkPill` — bordered, filled only while hovered — because by
/// the time it is drawn the scrim has faded the artwork into the page, so the
/// control it should match is the pill row below rather than a badge on a still.
///
/// A plain `Button`, so macOS full keyboard access can reach and press it. That is
/// as far as the keyboard goes on purpose: binding the arrow keys here would take
/// them from the scroll view that owns the rest of the screen.
private struct HeroPageButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(
                    isHovering ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
                )
                .frame(
                    width: Theme.Art.heroPageControl, height: Theme.Art.heroPageControl
                )
                .background(
                    isHovering ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .labelledHelp(label)
        .accessibilityLabel(label)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
    }
}
