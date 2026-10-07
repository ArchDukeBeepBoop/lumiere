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
                Text(shown)
                    .font(Theme.Font.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.xs)
                    .background(.black.opacity(0.55), in: .capsule)
                    .transition(.opacity)
            }
        }
        .padding(Theme.Space.xl)
        .allowsHitTesting(false)
        .task(id: model?.osd?.at) {
            guard let osd = model?.osd else { return }
            withAnimation(.easeOut(duration: 0.12)) { shown = osd.text }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { shown = nil }
        }
    }
}
