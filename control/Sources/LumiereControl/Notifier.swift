import Foundation
import UserNotifications

/// A notification when the server stops without being asked to.
///
/// The case a menu bar app is worst at: the icon changes from open to shut and
/// nobody is looking at the menu bar. The first anyone knows is a television
/// that cannot find its library. So this says so, once, at the moment it
/// happens.
///
/// Permission is asked for then too — not at launch. A prompt at first launch
/// asks for something before there is any reason to want it; asked at the
/// moment the server has just stopped, the reason is the notification itself.
@MainActor
final class Notifier {
    static let enabledKey = "notifyWhenServerStops"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func serverStopped(_ reason: String) {
        guard Self.isEnabled else { return }
        // The async API rather than the completion-handler one: the handler
        // runs on an arbitrary queue and would capture the notification centre
        // across it, which Swift 6 rightly calls a data race. Here everything
        // stays on the main actor and only the awaits leave it.
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            else { return }
            let content = UNMutableNotificationContent()
            content.title = "Lumiere Server stopped"
            content.body = reason
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "server-stopped",
                                                       content: content, trigger: nil))
        }
    }

    func serverBack() {
        guard Self.isEnabled else { return }
        // Replaces the "stopped" notice rather than stacking beside it: the
        // news is the current state, not a history of states.
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["server-stopped"])
    }
}
