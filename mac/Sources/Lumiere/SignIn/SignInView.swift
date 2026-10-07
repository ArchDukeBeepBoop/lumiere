import SwiftUI
import LumiereKit

struct SignInView: View {
    @Bindable var model: SignInModel
    // Not private: SignInView+Steps.swift draws the fields that bind to it, and
    // Swift's `private` is file-scoped.
    @FocusState var focused: Field?

    // Not private: SignInView+Steps.swift focuses these fields, and Swift's
    // `private` is file-scoped.
    enum Field { case address, username, password }

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()

            VStack(spacing: Theme.Space.xl) {
                Spacer()
                brand

                Group {
                    switch model.step {
                    case .server: serverStep
                    case .credentials: credentialsStep
                    }
                }
                .frame(width: 360)

                if let error = model.errorMessage {
                    Text(error)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.danger)
                        .multilineTextAlignment(.center)
                        .frame(width: 360)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                Spacer()
            }
        }
        .animation(Theme.Motion.transition, value: model.step)
        .animation(Theme.Motion.transition, value: model.quickConnectCode)
    }

    // MARK: - Brand

    var brand: some View {
        VStack(spacing: Theme.Space.md) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Palette.accent)
                .frame(width: 52, height: 52)
            Text("Lumiere")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(model.step == .server
                 ? "Connect to your Lumiere server"
                 : model.needsAccount ? "Welcome to \(model.serverDisplayName)" : "Sign in to \(model.serverDisplayName)")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.bottom, Theme.Space.sm)
    }
}
