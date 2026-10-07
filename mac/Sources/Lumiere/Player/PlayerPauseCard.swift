import SwiftUI
import LumiereKit

/// What is on screen while it is paused and left alone: the title, the
/// episode, and when it would end if it went on now — over a dimmed frame,
/// as the TV app does. Nothing is drawn while it plays.
struct PlayerPauseCard: View {
    let model: PlayerModel
    let isShown: Bool
    @State private var overview: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isShown {
                // The whole picture dimmed, then the lower half more, as
                // Apple TV's pause screen does — the frame stays legible
                // behind, the words are what is read.
                Color.black.opacity(0.3)
                LinearGradient(colors: [.clear, .black.opacity(0.7)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(model.title)
                        .font(Theme.Font.detailTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let line = model.subtitleLine {
                        Text(line)
                            .font(Theme.Font.detailMeta)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if let overview, !overview.isEmpty {
                        Text(overview)
                            .font(Theme.Font.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                            .frame(maxWidth: 640, alignment: .leading)
                            .padding(.top, Theme.Space.xs)
                    }
                    Text("Paused · \(model.remainingText.dropFirst()) left · ends \(endsAt) if resumed now")
                        .font(Theme.Font.body)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(Theme.Space.xxl)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: isShown)
        .task(id: model.itemId) {
            overview = try? await model.repository.entry(id: model.itemId)?.item.overview
        }
    }

    private var endsAt: String {
        let left = max(0, model.duration - model.position) / max(model.playbackSpeed, 0.1)
        return Date().addingTimeInterval(left).formatted(date: .omitted, time: .shortened)
    }
}
