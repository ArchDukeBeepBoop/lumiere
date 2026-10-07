import SwiftUI
import LumiereKit

/// The two steps of signing in: finding a server, then proving who you are.
///
/// Split from SignInView.swift for the project's 300-line limit.
extension SignInView {

    // MARK: - Step 1

    var serverStep: some View {
        VStack(spacing: Theme.Space.md) {
            discoveredServers

            // A generic example, not a specific address. The placeholder used to be
            // a plausible-looking LAN IP, which reads as a hint about *your*
            // network — and when it does not match, "couldn't reach the server" is
            // the least useful true statement available.
            field("Server address", text: $model.address, placeholder: "127.0.0.1:8098")
                .focused($focused, equals: .address)
                .onSubmit { Task { await model.connect() } }

            primaryButton(model.isBusy ? "Connecting…" : "Connect") {
                Task { await model.connect() }
            }
            .disabled(model.address.isEmpty || model.isBusy)

            Text("An IP address, a hostname, or the URL you use in a browser.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .onAppear { focused = .address }
        .task {
            await model.applyLaunchServerIfRequested()
            guard model.step == .server else { return }
            await model.findServers()
        }
    }

    @ViewBuilder
    private var discoveredServers: some View {
        if model.isDiscovering && model.discovered.isEmpty {
            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small)
                Text("Looking for servers on your network…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.discovered.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("On your network")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)

                ForEach(model.discovered) { server in
                    Button {
                        Task { await model.connect(to: server) }
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: "server.rack")
                                .foregroundStyle(Theme.Palette.accent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(server.name)
                                    .font(Theme.Font.cardTitle)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text(server.displayAddress)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textMuted)
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, Theme.Space.sm)
                        .background(Theme.Palette.surface, in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                }
            }
            .padding(.bottom, Theme.Space.xs)
        }
    }

    // MARK: - Step 2

    var credentialsStep: some View {
        VStack(spacing: Theme.Space.md) {
            if model.needsAccount {
                firstAccountFields
            } else if let code = model.quickConnectCode {
                quickConnectPanel(code: code)
            } else {
                if !model.publicUsers.isEmpty {
                    userPicker
                }

                field("Username", text: $model.username, placeholder: "")
                    .focused($focused, equals: .username)
                    .onSubmit { focused = .password }

                secureField("Password", text: $model.password)
                    .focused($focused, equals: .password)
                    .onSubmit { Task { await model.signIn() } }

                primaryButton(model.isBusy ? "Signing in…" : "Sign in") {
                    Task { await model.signIn() }
                }
                .disabled(!model.canSubmitCredentials)

                if model.quickConnectAvailable {
                    secondaryButton("Use Quick Connect instead") {
                        model.startQuickConnect()
                    }
                }
            }

            secondaryButton("Use a different server") {
                model.backToServer()
            }
        }
        .onAppear { if model.username.isEmpty { focused = .username } }
    }

    private var userPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(model.publicUsers) { user in
                    Button {
                        model.username = user.name
                        focused = .password
                    } label: {
                        VStack(spacing: Theme.Space.xs) {
                            Circle()
                                .fill(model.username == user.name
                                      ? Theme.Palette.accent
                                      : Theme.Palette.surfaceRaised)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(initials(of: user.name))
                                        .font(Theme.Font.cardTitle)
                                        .foregroundStyle(model.username == user.name
                                                         ? Theme.Palette.onAccent
                                                         : Theme.Palette.textSecondary)
                                )
                            Text(user.name)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Theme.Space.xs)
        }
        .frame(height: 72)
    }

    private func quickConnectPanel(code: String) -> some View {
        VStack(spacing: Theme.Space.md) {
            Text("Enter this code in Lumiere on a device you're already signed in on.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(code)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Palette.accent)
                .tracking(6)
                .padding(.vertical, Theme.Space.md)
                .frame(maxWidth: .infinity)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            HStack(spacing: Theme.Space.sm) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }

            secondaryButton("Cancel") { model.cancelQuickConnect() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Controls

    func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
    }

    func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
            SecureField("", text: text)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
    }

    func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.sm + 2)
                .background(Theme.Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(.plain)
    }

    func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func initials(of name: String) -> String {
        String(name.prefix(2)).uppercased()
    }
}
