import SwiftUI

/// The player's glass vocabulary, as Apple TV and visionOS draw it over video:
/// a segmented picker whose selection slides, menu rows with a leading tick and
/// a second line of detail, section labels, and switch rows with a glyph.
///
/// Every panel in the player is built from these, so the audio menu, the
/// settings panel and the queue cannot drift into three different looks — the
/// way the old opaque settings sheet and the black-slab menus had.

/// Tabs as a capsule with a white thumb that slides between them.
struct PlayerSegmented<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var icon: ((Item) -> String)? = nil
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item == selection
                Button {
                    withAnimation(Theme.Motion.segment) { selection = item }
                } label: {
                    HStack(spacing: 5) {
                        if let icon { Image(systemName: icon(item)).font(Theme.Glyph.sm(.semibold)) }
                        Text(title(item)).font(Theme.Font.playerTab).lineLimit(1)
                    }
                    .padding(.horizontal, Theme.Space.sm + 2)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Theme.PlayerPalette.segmentOnThumb : Theme.Palette.onPlayerChrome)
                    .background {
                        if on {
                            Capsule().fill(Theme.PlayerPalette.segmentThumb)
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.PlayerPalette.segmentTrack))
    }
}

/// A small heading over a group of rows, as in a tvOS menu column.
struct PlayerSectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.playerSection)
            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, 2)
    }
}

/// A switch with a glyph and a line of explanation, tinted like the scrubber.
struct PlayerSwitchRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(Theme.Glyph.md(.medium))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.PlayerPalette.glyphPlate))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.playerRow.weight(.medium))
                if let detail {
                    Text(detail).font(Theme.Font.playerDetail)
                        .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Theme.PlayerPalette.scrubPlayed)
        }
        .foregroundStyle(Theme.Palette.onPlayerChrome)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 4)
    }
}

/// What a track says about itself on its second line: `AC3 · 5.1 · Default`.
enum TrackDetail {
    static func line(codec: String?, channels: Int?, isDefault: Bool, isForced: Bool) -> String? {
        var parts: [String] = []
        if let codec, !codec.isEmpty { parts.append(codec.uppercased()) }
        if let channels {
            switch channels {
            case 1: parts.append("Mono")
            case 2: parts.append("Stereo")
            case 6: parts.append("5.1")
            case 8: parts.append("7.1")
            default: parts.append("\(channels) ch")
            }
        }
        if isForced { parts.append("Forced") }
        if isDefault { parts.append("Default") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One row of a player menu, as a tvOS or macOS menu draws it: a tick column
/// that keeps its width, the name, a quieter second line, and a value at the
/// trailing edge. No permanent fill — forty chapters are forty lines, not a
/// wall of slabs.
struct PlayerPanelRow: View {
    let title: String
    let detail: String?
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "checkmark")
                    .font(Theme.Glyph.md(.bold))
                    .foregroundStyle(Theme.Palette.onPlayerChrome)
                    .frame(width: 14)
                    .opacity(selected ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.Font.playerRow.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Theme.Palette.onPlayerChrome)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Font.playerDetail)
                            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.sm)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.Font.playerRow)
                        .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovering ? Theme.PlayerPalette.menuHover : Theme.PlayerPalette.menuSelected)
                    .opacity(isHovering || selected ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
    }
}
