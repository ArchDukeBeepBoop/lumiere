import Foundation
import LumiereKit

/// When the app stops looking like it is starting up.
///
/// Split from AppModel.swift for the project's 300-line rule.
extension AppModel {

    /// Logs how long the launch screen was up. Called when the home screen reports
    /// its first load.
    func noteReady() {
        guard !didNoteReady else { return }
        didNoteReady = true
        let seconds = Date().timeIntervalSince(startedAt)
        Diagnostics.log(String(format: "[launch] ready in %.2fs", seconds))
    }

    /// Whether the app is finished starting up and worth showing.
    ///
    /// Deliberately not "the sync has finished": a full pass over 45,000 items is
    /// minutes, and a splash that sits there for minutes is a hang. This is the
    /// point where every service is up and the first screen is drawn — the sync
    /// carries on behind it with its own progress in the sidebar.
    ///
    /// The empty-library clause is for a first-ever launch, where there is no cache
    /// to read and the only thing that can fill the home screen is the sync. Held
    /// there rather than revealing an empty app that looks like it found nothing.
    var isReady: Bool { repository != nil && !libraries.isEmpty && homeDidLoad }
}
