import Foundation

/// Runs work with a deadline, returning nil if it does not finish in time.
///
/// URLSession's own timeout is 20 seconds, which is right for a library sync and
/// far too long for anything a person is waiting on. Where a cached answer
/// exists, waiting 20 seconds to discover the server is asleep is strictly worse
/// than using it after two.
public enum Timeout {

    public static func run<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }

            let first = await group.next() ?? nil
            // Cancel the loser so a slow request does not outlive the caller.
            group.cancelAll()
            return first
        }
    }
}
