import SwiftUI
import LumiereKit
import LumierePlayer

/// The player's settings as a sidebar down the right edge, in four tabs —
/// Subtitles, Audio, Video, Playback — the layout the VLC redesign argued
/// for: what you adjust while watching sits beside the picture rather than in
/// a box over the middle of it, and every value is a slider or a list, never
/// a number to type.
///
/// Replaces the two-column gear panel. Its controls are all here, plus the
/// ones VLC hid in Tools › Effects and Filters.
struct PlayerSidebar: View {
    let model: PlayerModel
    @Binding var isPresented: Bool
    var playerSize: CGSize = .zero

    @AppStorage("playerSidebarTab") private var tabRaw = Tab.subtitles.rawValue

    enum Tab: String, CaseIterable, Identifiable {
        case subtitles, audio, video, playback
        var id: String { rawValue }
        var title: String {
            switch self {
            case .subtitles: return "Subtitles"
            case .audio: return "Audio"
            case .video: return "Video"
            case .playback: return "Playback"
            }
        }
    }

    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: tabRaw) ?? .subtitles }, set: { tabRaw = $0.rawValue })
    }

    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    switch tab.wrappedValue {
                    case .subtitles: PlayerSidebarSubtitles(model: model)
                    case .audio: PlayerSidebarAudio(model: model)
                    case .video: PlayerSidebarVideo(model: model)
                    case .playback: PlayerSidebarPlayback(model: model)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.lg)
            }
            presetFooter
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .playerSurface(cornerRadius: Theme.Radius.playerGlass)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(spacing: Theme.Space.md) {
            HStack {
                Text("Settings")
                    .font(Theme.Font.playerTitle)
                    .foregroundStyle(Theme.Palette.onPlayerChrome)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(Theme.Glyph.sm(.bold))
                        .foregroundStyle(Theme.Palette.onPlayerChrome)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.PlayerPalette.segmentTrack))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .labelledHelp("Close settings")
            }
            PlayerSegmented(items: Tab.allCases, selection: tab, title: \.title)
        }
        .padding(Theme.Space.md)
    }

    /// Save for This Show: the whole sidebar, kept for every episode.
    private var presetFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Rectangle().fill(Theme.PlayerPalette.surfaceStroke).frame(height: 1)
            HStack(spacing: Theme.Space.sm) {
                Button {
                    Task { await model.saveShowPreset() }
                } label: {
                    Label(model.hasShowPreset ? "Update Show Preset" : "Save for This Show",
                          systemImage: "square.and.arrow.down")
                        .font(Theme.Font.playerRow.weight(.medium))
                }
                .buttonStyle(PlayerCapsuleButtonStyle(prominent: true))
                if model.hasShowPreset {
                    Button("Forget") { Task { await model.forgetShowPreset() } }
                        .buttonStyle(PlayerCapsuleButtonStyle(prominent: false))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
            Text("Subtitle timing, look and position, audio delay, picture and sound — applied to every episode.")
                .font(Theme.Font.playerDetail)
                .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.md)
        }
    }
}

/// A capsule button on the player's glass: white for the main action,
/// smoked for the rest — the tvOS pair.
struct PlayerCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Theme.PlayerPalette.segmentOnThumb : Theme.Palette.onPlayerChrome)
            .background(Capsule().fill(prominent ? Theme.PlayerPalette.segmentThumb : Theme.PlayerPalette.segmentTrack))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
