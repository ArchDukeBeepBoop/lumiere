import Foundation

/// Deciding when the scan you just asked for is over.
///
/// A pure function because the rule is subtle and the failure is silent: poll
/// immediately after asking and the server may not have started yet, so it
/// answers "not running" and a naive caller calls the scan finished before it
/// began — then syncs an unchanged library and reports success. Which is exactly
/// the shape of bug this whole area has had.
public enum ServerScanWait {

    /// Whether the scan has ended.
    ///
    /// - `sawItRun`: whether any earlier poll in this wait saw it running. That
    ///   is the strongest signal there is — it started and has now stopped.
    /// - `before`: the status read *before* the scan was requested. When the run
    ///   was never observed (it can begin and end between two polls), a finish
    ///   time that has moved since then is what says it happened.
    public static func isFinished(
        status: ServerScanStatus, before: ServerScanStatus?, sawItRun: Bool
    ) -> Bool {
        if status.Running { return false }
        if sawItRun { return true }
        return status.LastFinished != before?.LastFinished
    }
}
