import SwiftUI

/// What stays when the controls fade: a hairline of progress and the time
/// left, for a few seconds, then nothing — tvOS's way of letting go of the
/// picture gradually instead of all at once.
struct PlayerGlance: View {
    let model: PlayerModel
    let isShown: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Spacer()
            Text(model.remainingText)
                .font(Theme.Font.playerTimecode)
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.6), radius: 4)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: geometry.size.width * model.progressFraction)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.xl)
        .opacity(isShown ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: isShown)
        .allowsHitTesting(false)
    }
}
