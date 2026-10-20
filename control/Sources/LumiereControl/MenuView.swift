import AppKit
import ControlCore
import SwiftUI

/// The menu behind the icon, laid out as macOS lays out its own menu bar extras.
///
/// A header that states the one fact you clicked to learn. Two Control Center
/// tiles for the two things you came to switch. A module card for the library.
/// Grouped rows with circled icons. And at the foot, plain commands with their
/// key equivalents — Restart, Show Log, Settings…, Quit — exactly where the
/// Wi-Fi and Bluetooth menus put theirs, so nothing here has to be learned.
struct MenuView: View {
    @Bindable var server: ServerProcess
    @Bindable var lumiere: AppLauncher
    @Bindable var backups: BackupRestorer
    @Bindable var monitor: LibraryMonitor

    @Environment(\.openSettings) private var openSettings
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tiles.padding(.horizontal, Menu.gutter).padding(.top, 10)
            LibraryCard(stats: monitor.stats)
                .padding(.horizontal, Menu.gutter).padding(.top, 8)
            MenuSection(text: "Sharing")
            sharing
            MenuSection(text: "Backups")
            BackupRows(backups: backups, server: server)
            MenuRule()
            commands
        }
        .padding(.vertical, 8)
        .frame(width: Menu.width)
        .task { await monitor.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: IrisIcon.image(openness: serving ? 1 : 0, size: 34))
                .id(serving)
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lumiere Server").font(Menu.title)
                status
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Menu.gutter + 2)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.35), value: serving)
    }

    private var serving: Bool { server.state == .running }

    @ViewBuilder private var status: some View {
        Group {
            switch server.state {
            case .running where monitor.stats?.isPlaying == true:
                HStack(spacing: 4) {
                    // Animated only while the menu is open — the menu bar itself
                    // never moves, which is a courtesy the system extends too.
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                    Text("Playing · background work paused")
                }
                .foregroundStyle(Menu.accent)
            case .running:
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(uptime(at: context.date))
                }
            case .starting:
                Text("Starting…")
            case .stopped:
                Text("Stopped")
            case .failed(let why):
                Text(why).foregroundStyle(.red)
            }
        }
        .font(Menu.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    private func uptime(at now: Date) -> String {
        guard let since = server.startedAt else { return "Serving" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        f.allowedUnits = [.day, .hour, .minute]
        let span = max(60, now.timeIntervalSince(since))
        return "Serving · up \(f.string(from: span) ?? "")"
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 8) {
            Tile(symbol: "power", title: "Server", state: serverWord,
                 active: serving, busy: server.state == .starting) {
                if serving || server.state == .starting { server.stop() } else { server.start() }
            }
            Tile(symbol: "play.rectangle.fill", title: "Lumiere",
                 state: !lumiere.isInstalled ? "Not installed" : lumiere.isRunning ? "Open" : "Closed",
                 active: lumiere.isRunning) {
                guard lumiere.isInstalled else { return }
                if lumiere.isRunning { lumiere.quit() } else { lumiere.launch() }
            }
            .disabled(!lumiere.isInstalled)
        }
    }

    private var serverWord: String {
        switch server.state {
        case .running: "On"
        case .starting: "Starting"
        case .stopped: "Off"
        case .failed: "Stopped"
        }
    }

    // MARK: - Sharing

    @ViewBuilder private var sharing: some View {
        let local = "127.0.0.1:8098"
        MenuRow(symbol: "desktopcomputer", title: "This Mac",
                detail: copied == local ? "Copied" : local) { copy(local) }
        if monitor.stats?.listensOnNetwork == true, let ip = monitor.lanAddress {
            let lan = "\(ip):8098"
            MenuRow(symbol: "wifi", title: "Home Network", subtitle: "TV and phone connect here",
                    detail: copied == lan ? "Copied" : lan, active: serving) { copy(lan) }
        } else {
            MenuRow(symbol: "wifi.slash", title: "Home Network",
                    subtitle: "Off — turn on in Lumiere's Settings", isEnabled: false) {}
        }
    }

    private func copy(_ address: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://" + address, forType: .string)
        withAnimation { copied = address }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { if copied == address { copied = nil } }
        }
    }

    // MARK: - Commands

    @ViewBuilder private var commands: some View {
        MenuCommand(title: "Restart Server", key: "r", isEnabled: server.state != .starting) {
            Task { await server.restart() }
        }
        MenuCommand(title: "Show Server Log") { showLog() }
        MenuCommand(title: "Show Library in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([LibraryMonitor.database])
        }
        MenuRule()
        MenuCommand(title: "Settings…", key: ",") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        // Named for what it is. Quitting a menu bar app is not obviously the
        // same as stopping a server; the Settings window says so in full.
        MenuCommand(title: "Quit Lumiere Control", key: "q") {
            server.stop()
            NSApplication.shared.terminate(nil)
        }
    }

    /// In Console, which is where a Mac keeps logs and what it opens them in.
    private func showLog() {
        let log = LibraryMonitor.logFile
        let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        guard FileManager.default.fileExists(atPath: log.path) else {
            NSWorkspace.shared.open(log.deletingLastPathComponent())
            return
        }
        NSWorkspace.shared.open([log], withApplicationAt: console,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
