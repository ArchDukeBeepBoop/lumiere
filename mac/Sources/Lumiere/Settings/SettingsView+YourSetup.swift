import SwiftUI
import LumiereKit

/// Your Setup: what this Lumiere is made of — the libraries and the folders
/// feeding them, the rooms, the account, and every setting you have changed
/// from how Lumiere comes. The setup guide reopens from here.
extension SettingsView {
    @ViewBuilder
    var yourSetupForm: some View {
        SettingsCard(title: "Setup Guide", icon: "sparkles",
                     subtitle: "Libraries, rooms, details and a few choices, step by step") {
            SettingsNote("Walks through adding libraries, choosing what goes in the Private Room, posters and details, and a few first choices. Anything you set there shows up here.")
            Button("Open Setup Guide") { app.isShowingSetupGuide = true }
        }
        SettingsCard(title: "Libraries & Folders", icon: "externaldrive",
                     subtitle: "Every library on your server and the folders it reads") {
            if app.client == nil {
                SettingsNote("Connect to your server to manage its libraries.")
            } else {
                ServerLibraryEditor(app: app)
            }
        }
        YourChangesCard()
        AccountCard(app: app)
    }
}

/// Every setting that differs from how Lumiere comes, each with its own way
/// back, and the private libraries by name.
struct YourChangesCard: View {
    @State private var changes: [(SettingsCatalog.Entry, Any)] = SettingsCatalog.changed()

    var body: some View {
        SettingsCard(title: "Your Changes", icon: "checklist",
                     subtitle: "\(changes.count) \(changes.count == 1 ? "setting differs" : "settings differ") from how Lumiere comes") {
            if changes.isEmpty {
                SettingsNote("Everything is as Lumiere comes. Change anything in Settings and it is listed here.")
            }
            ForEach(Array(Dictionary(grouping: changes, by: { $0.0.section }).sorted { $0.key < $1.key }), id: \.key) { section, rows in
                Text(section).font(Theme.Font.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textMuted)
                    .padding(.top, Theme.Space.xs)
                ForEach(rows, id: \.0.key) { entry, value in
                    HStack {
                        Text(entry.label)
                        Spacer()
                        Text(SettingsCatalog.describe(value)).foregroundStyle(Theme.Palette.textSecondary)
                        Text("was \(SettingsCatalog.describe(entry.fallback))")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                        Button("Reset") { UserDefaults.standard.removeObject(forKey: entry.key) }
                            .buttonStyle(.link).font(Theme.Font.caption)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            changes = SettingsCatalog.changed()
        }
    }
}

/// Who is signed in, and changing the password.
struct AccountCard: View {
    let app: AppModel
    @State private var current = ""
    @State private var new = ""
    @State private var message: String?
    @State private var devices: [SignedInDevice] = []

    var body: some View {
        SettingsCard(title: "Account", icon: "person.crop.circle") {
            if let session = app.client?.session {
                LabeledContent("Signed in as", value: session.userName)
                LabeledContent("Server", value: "\(session.serverName) · \(session.serverURL.host ?? "")")
            }
            SecureField("Current password", text: $current)
            SecureField("New password", text: $new)
            HStack {
                Button("Change Password") { Task { await change() } }
                    .disabled(current.isEmpty || new.count < 8)
                if let message { Text(message).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary) }
            }
            if !new.isEmpty, new.count < 8 {
                Text("At least 8 characters.").font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
            }
            Divider()
            Text("Signed-in devices").font(Theme.Font.body.weight(.semibold))
            SettingsNote("Sign out anything you no longer use, or have lost. A device unused for 90 days is signed out by itself.")
            ForEach(devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.device.isEmpty ? device.client : device.device)
                        Text(device.current ? "This Mac" : "\(device.client) · last used \(Self.when(device.lastSeen))")
                            .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                    }
                    Spacer()
                    if !device.current {
                        Button("Sign Out") {
                            Task {
                                try? await app.client?.signOutDevice(device.id)
                                await loadDevices()
                            }
                        }
                    }
                }
            }
        }
        .task { await loadDevices() }
    }

    private func loadDevices() async {
        devices = (try? await app.client?.signedInDevices()) ?? []
    }

    private static func when(_ stamp: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: stamp) else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }

    private func change() async {
        do {
            try await app.client?.changePassword(current: current, new: new)
            current = ""
            new = ""
            message = "Changed. Your other devices stay signed in."
        } catch {
            message = "Not changed — check the current password."
        }
    }
}
