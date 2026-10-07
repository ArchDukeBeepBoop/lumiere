import SwiftUI

/// The building blocks Settings is drawn from.
///
/// Replaces `Form`/`Section` with the app's own tokens. The stock grouped form is
/// the right call where a window should disappear into the system — but Settings is
/// a room people spend time in, and next to the rest of Lumiere the default styling
/// read as a different application: system greys against the canvas, its own
/// typography, its own spacing.
///
/// Everything here is layout and colour only. It deliberately keeps native controls
/// — pickers, toggles, sliders — because reimplementing those loses focus rings,
/// keyboard behaviour and accessibility for the sake of appearance.
struct SettingsCard<Content: View, Accessory: View>: View {
    let title: String
    var icon: String?
    var subtitle: String?
    /// A control belonging to the card as a whole rather than to any one row —
    /// "Forget All" over a list, for instance. Sits in the header so it reads as
    /// acting on everything below it.
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    @Environment(\.settingsHighlight) private var highlighted
    @Environment(\.settingsOpenCard) private var openCard
    @State private var isPage = false

    /// A section, not a box.
    ///
    /// Every card had a fill, a border and a radius, so Settings was cards
    /// inside a scroll view inside a window — "everything is a card", which the
    /// design review names as the plainest breach of the language: Apple TV uses
    /// almost none, it uses space and one line of type. So each group is now its
    /// heading, a hairline above it, and its rows on the canvas itself. A search
    /// result still marks its section, with a wash instead of a ring.
    /// On its pane: the section, or its row when it is long. On a page: the
    /// section alone, or nothing when another section has the page. See
    /// `SettingsPages`.
    var body: some View {
        if let open = openCard.wrappedValue {
            if open == title { section }
        } else if isPage || SettingsPages.isPage(title) {
            SettingsPageRow(title: title, icon: icon, subtitle: subtitle) {
                openCard.wrappedValue = title
            }
        } else {
            section
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    SettingsPages.heights[title] = height
                    if height > SettingsPages.pageThreshold { isPage = true }
                }
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 1)
                .opacity(0.7)
            header
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                content
            }
            .padding(.leading, icon == nil ? 0 : 22 + Theme.Space.sm)
        }
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.sm)
        .background(
            isHighlighted ? Theme.Palette.accent.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card)
        )
        // The section's own title is its scroll anchor, so a search result can
        // put the setting it named on screen instead of dropping you at the top
        // of a long pane to hunt for it by eye.
        .id(title)
        .animation(Theme.Motion.hover, value: isHighlighted)
    }

    /// True while a search result has just pointed here.
    ///
    /// Scrolling alone is not enough on a long pane: the card arrives somewhere
    /// in the middle of the window with nothing marking it as the answer.
    private var isHighlighted: Bool { highlighted == title }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            if let icon {
                SettingsIconChip(icon)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

/// The tinted rounded square every settings icon sits in.
///
/// Borrowed from tvOS and iOS Settings, where the chip is what turns a column of
/// glyphs into a legible list: a bare SF Symbol has no consistent optical weight —
/// `key` is thin and `speaker.wave.3` is wide — so a stack of them reads as ragged
/// no matter how carefully they are aligned. A fixed plate makes every row the same
/// shape, and the glyph inside it can then be whatever size suits it.
struct SettingsIconChip: View {
    let name: String
    var size: CGFloat = 22
    /// Filled with the accent when the row it marks is selected, tinted otherwise.
    var isProminent = false

    init(_ name: String, size: CGFloat = 22, isProminent: Bool = false) {
        self.name = name
        self.size = size
        self.isProminent = isProminent
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(isProminent
                  ? AnyShapeStyle(Theme.Palette.accent)
                  : AnyShapeStyle(Theme.Palette.accent.opacity(0.16)))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: name)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(isProminent
                                     ? Theme.Palette.onAccent : Theme.Palette.accent)
            }
    }
}

extension SettingsCard where Accessory == EmptyView {
    init(
        title: String,
        icon: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, icon: icon, subtitle: subtitle,
            accessory: { EmptyView() }, content: content
        )
    }
}

/// A labelled row. The label column is fixed so controls line up down the card
/// rather than each finding its own left edge.
struct SettingsRow<Control: View>: View {
    let label: String
    var help: String?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                Text(label)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: 150, alignment: .leading)
                control
                    .labelsHidden()
                Spacer(minLength: 0)
            }
            if let help {
                Text(help)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    // Aligned to the control column, so explanations read as
                    // belonging to the setting rather than to the card.
                    .padding(.leading, 150 + Theme.Space.md)
            }
        }
    }
}

/// A short line of explanation between rows.
struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        SettingsExplanation(text)
    }
}

/// A setting's explanation: its first sentence, with the rest a "?" away.
///
/// Settings carried three-sentence notes under nearly every toggle — the
/// "wall" the design review asked to take down. The first sentence says what
/// the setting does; the rest says why, and is there for whoever wants it, on
/// hover or click, rather than read by everyone on the way past.
struct SettingsExplanation: View {
    let text: String
    @State private var isShowingAll = false

    init(_ text: String) { self.text = text }

    var body: some View {
        let (first, rest) = Self.split(text)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
            Text(first)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !rest.isEmpty {
                Button { isShowingAll.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
                .buttonStyle(.plain)
                .help(text)
                .popover(isPresented: $isShowingAll, arrowEdge: .trailing) {
                    Text(text)
                        .font(Theme.Font.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 320, alignment: .leading)
                        .padding(Theme.Space.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first sentence, and everything after it. A short note stays whole.
    static func split(_ text: String) -> (String, String) {
        guard text.count > 110, let end = text.range(of: ". ") else { return (text, "") }
        return (String(text[..<end.lowerBound]) + ".", String(text[end.upperBound...]))
    }
}


/// Which card a Settings search result just pointed at, if any.
///
/// In the environment because the cards are built across four files and none of
/// them takes a parameter for it; a card should not have to be rewired to be
/// findable.
private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsHighlight: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}
