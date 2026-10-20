import AppKit
import SwiftUI

/// Lumiere Control's Settings window — the "… Settings…" every Mac menu bar
/// extra ends with, so the menu can stay a menu.
///
/// Grouped forms in the style of System Settings: a label on the left, the
/// control on the right, a sentence of explanation under anything whose
/// consequence is not obvious.
struct SettingsView: View {
    @Bindable var loginItem: LoginItem
    let server: ServerProcess

    var body: some View {
        TabView {
            GeneralPane(loginItem: loginItem)
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutPane(server: server)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
        // An accessory app's window opens behind whatever is in front unless
        // the app is brought forward with it.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

private struct GeneralPane: View {
    @Bindable var loginItem: LoginItem
    @AppStorage(Notifier.enabledKey) private var notify = true

    var body: some View {
        Form {
            Section {
                Toggle("Start the server when you log in", isOn: Binding(
                    get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if let problem = loginItem.problem {
                    Text(problem).foregroundStyle(.red).font(.callout)
                }
            } footer: {
                Text("Lumiere Control opens in the menu bar and starts the server. "
                     + "Lumiere itself stays closed until you open it.")
            }

            Section {
                Toggle("Notify me if the server stops", isOn: $notify)
            } footer: {
                Text("Only when it stops on its own — a television that cannot find "
                     + "the library is usually the first sign otherwise.")
            }

            Section {
                LabeledContent("Library") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([LibraryMonitor.database])
                    }
                }
                LabeledContent("Server log") {
                    Button("Open in Console") {
                        NSWorkspace.shared.open(
                            [LibraryMonitor.logFile],
                            withApplicationAt: URL(fileURLWithPath:
                                "/System/Applications/Utilities/Console.app"),
                            configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            } footer: {
                Text("Quitting Lumiere Control stops the server. Your library and "
                     + "watch history are kept either way.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 360)
    }
}

private struct AboutPane: View {
    let server: ServerProcess
    @State private var serverVersion: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: IrisIcon.image(openness: 1, size: 96))
            Text("Lumiere Control").font(.title2.weight(.semibold))
            Text("Version \(Self.version)").foregroundStyle(.secondary)
            if let serverVersion {
                Text(serverVersion).font(.callout).foregroundStyle(.tertiary)
            }
            Text("Starts, stops and looks after the server behind Lumiere.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .task { serverVersion = await Self.fetchServerVersion() }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    /// Asked of the server rather than read from disk, so it describes the one
    /// actually answering — which after an install is the one that matters.
    static func fetchServerVersion() async -> String? {
        guard let url = URL(string: "http://127.0.0.1:8098/System/Info/Public"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "Server not running" }
        let version = json["Version"] as? String ?? "?"
        let level = (json["LumiereAPI"] as? Int).map { " · API level \($0)" } ?? ""
        return "Lumiere Server \(version)\(level)"
    }
}
