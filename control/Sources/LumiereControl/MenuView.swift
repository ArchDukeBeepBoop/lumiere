import AppKit
import SwiftUI

/// The menu behind the icon.
///
/// One screen, no submenus, no window. Everything here is something you do while
/// standing up — start the server, open the app, run an import — and a menu bar
/// item that needs navigating is one you stop using.
///
/// The layout is a single column on a fixed grid: a header that states the one
/// fact worth knowing, then groups separated by space rather than by rules. The
/// only divider in the whole menu is above Quit, because that is the only place
/// a mistaken click costs anything.
struct MenuView: View {
    @Bindable var server: ServerProcess
    @Bindable var lumiere: AppLauncher
    @Bindable var loginItem: LoginItem
    @Bindable var backups: BackupRestorer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MenuSection(text: "Server")
            VStack(alignment: .leading, spacing: 0) { serverRows }.menuPanel()
            MenuSection(text: "Lumiere")
            VStack(alignment: .leading, spacing: 0) { appRows }.menuPanel()
            MenuSection(text: "Library")
            VStack(alignment: .leading, spacing: 0) {
                BackupRows(backups: backups, server: server)
            }
            .menuPanel()
            footer
        }
        .padding(.vertical, 10)
        .frame(width: Menu.width)
        .modifier(MenuLookBackground())
    }

    // MARK: - Header

    /// The status, given the most room in the menu because it is the answer to
    /// the question that made you click.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lumiere")
                .font(Menu.title)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColour)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(Menu.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Menu.gutter)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var statusColour: Color {
        switch server.state {
        case .running: Menu.accent
        case .starting: .secondary
        case .failed: .red
        case .stopped: Color.primary.opacity(0.25)
        }
    }

    private var statusText: String {
        switch server.state {
        case .running: "Serving on 127.0.0.1:8098"
        case .starting: "Starting…"
        case .stopped: "Not running"
        case .failed(let why): why
        }
    }

    // MARK: - Sections

    @ViewBuilder private var serverRows: some View {
        if server.state == .running || server.state == .starting {
            MenuRow(symbol: "stop.circle", title: "Stop Server") { server.stop() }
        } else {
            MenuRow(symbol: "play.circle", title: "Start Server") { server.start() }
        }
        MenuRow(symbol: "link", title: "Copy Address", detail: "127.0.0.1:8098") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(server.address.absoluteString, forType: .string)
        }
    }

    @ViewBuilder private var appRows: some View {
        if !lumiere.isInstalled {
            MenuNote(symbol: "exclamationmark.triangle", text: "Lumiere is not installed.")
        } else if lumiere.isRunning {
            MenuRow(symbol: "xmark.circle", title: "Quit Lumiere") { lumiere.quit() }
        } else {
            MenuRow(symbol: "play.rectangle", title: "Open Lumiere") { lumiere.launch() }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuSection(text: "Options")
            loginToggle
            MenuLookRow()
            if let problem = loginItem.problem {
                MenuNote(symbol: nil, text: problem, tint: .red)
            }
            Divider()
                .padding(.horizontal, Menu.gutter)
                .padding(.top, 10)
                .padding(.bottom, 6)
            // Named plainly. It is not obvious that closing a menu bar app stops
            // a server, and the alternative — orphaning it on port 8098 — is
            // worse and harder to explain after the fact.
            MenuRow(symbol: "power", title: "Quit", detail: "stops the server") {
                server.stop()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// A toggle laid out on the same grid as the rows, so the column of labels
    /// stays unbroken. A stock Toggle would indent differently and the eye
    /// notices immediately.
    private var loginToggle: some View {
        HStack(spacing: 0) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 13))
                .frame(width: Menu.iconColumn, alignment: .leading)
            Text("Start server at login")
                .font(Menu.body)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.set($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, Menu.gutter)
        .frame(height: Menu.rowHeight)
    }
}
