import SwiftUI
import LumiereKit

/// The second step on a brand-new server: there is no one to sign in as yet,
/// so the first person makes the account everything else will use.
extension SignInView {
    var firstAccountFields: some View {
        VStack(spacing: Theme.Space.md) {
            Text("This server is new. Choose the name and password you’ll sign in with — on this Mac, your phone and your TV.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            field("Your name", text: $model.username, placeholder: "")
                .focused($focused, equals: .username)
                .onSubmit { focused = .password }
            secureField("Password", text: $model.password)
                .focused($focused, equals: .password)
            secureField("Password again", text: $model.confirmPassword)
                .onSubmit { Task { await model.createAccount() } }

            if !model.confirmPassword.isEmpty, model.password != model.confirmPassword {
                Text("The two passwords differ.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.danger)
            }

            primaryButton(model.isBusy ? "Creating…" : "Create Account") {
                Task { await model.createAccount() }
            }
            .disabled(!model.canCreateAccount)
        }
    }
}
