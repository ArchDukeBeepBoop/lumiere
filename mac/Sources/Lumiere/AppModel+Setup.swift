import Foundation
import LumiereKit

/// When the first-run guide opens by itself.
@MainActor
extension AppModel {
    /// On a server with no libraries, unless the guide was finished or put
    /// off; and always right after the server's first account was made.
    func offerSetupIfNew() async {
        let defaults = UserDefaults.standard
        // The shell can appear a moment before the session is restored.
        for _ in 0..<20 where client == nil { try? await Task.sleep(for: .milliseconds(500)) }
        if defaults.object(forKey: SetupGuide.doneKey) as? Bool == false {
            isShowingSetupGuide = true
            return
        }
        guard defaults.object(forKey: SetupGuide.doneKey) == nil, let client,
              let libraries = try? await client.serverLibraries() else { return }
        if libraries.isEmpty {
            isShowingSetupGuide = true
        } else {
            // A server already in use: nothing to guide.
            defaults.set(true, forKey: SetupGuide.doneKey)
        }
    }
}
