import SwiftUI
import LumiereKit

/// What a menu command just did, said on screen for a moment — "Audio +0.3 s",
/// "Speed 1.25×", "Frame copied". Menu commands were silent otherwise: the
/// only way to know an offset had changed was to open the menu again.
struct PlayerOSD: View {
    let model: PlayerModel?
    @State private var shown: String?

    var body: some View {
        Group {
            if let shown {
                // A glass capsule with a glyph, as macOS draws its own volume
                // and brightness HUDs — not a black lozenge of caption text.
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: Self.icon(for: shown))
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(shown)
                        .font(Theme.Font.playerRow.weight(.semibold))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .padding(.horizontal, Theme.Space.md + 2)
                .padding(.vertical, Theme.Space.sm)
                .playerSurface(cornerRadius: 22)
                .environment(\.colorScheme, .dark)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(Theme.Space.xl)
        .allowsHitTesting(false)
        .task(id: model?.osd?.at) {
            guard let osd = model?.osd else { return }
            withAnimation(Theme.Motion.segment) { shown = osd.text }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { shown = nil }
        }
    }

    /// The glyph for what the message is about, read from its first word.
    static func icon(for text: String) -> String {
        let lower = text.lowercased()
        let table: [(String, String)] = [
            ("speed", "gauge.with.dots.needle.67percent"), ("audio", "speaker.wave.2"),
            ("volume", "speaker.wave.2"), ("mute", "speaker.slash"), ("subtitle", "captions.bubble"),
            ("copied", "doc.on.doc"), ("loop", "repeat"), ("chapter", "list.bullet.rectangle"),
            ("aspect", "aspectratio"), ("zoom", "plus.magnifyingglass"), ("screenshot", "camera"),
            ("frame", "camera"), ("sleep", "moon.zzz"), ("flip", "arrow.left.and.right"),
        ]
        return table.first { lower.contains($0.0) }?.1 ?? "info.circle"
    }
}
