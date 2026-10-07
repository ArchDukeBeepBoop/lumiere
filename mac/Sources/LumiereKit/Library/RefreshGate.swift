import Foundation

/// At most one refresh running, and at most one more behind it.
///
/// A single tick on an episode announces itself several times — the write,
/// the database watcher, the server's confirmation — and each announcement
/// cancelled the refresh before it and started another. The home screen, which
/// asks the server for Next Up, spent the whole time rebuilding and threw every
/// answer away. Now a request while one is running only marks the screen dirty,
/// and one more refresh follows when it finishes: every change lands, and the
/// work is done at most twice however many times it was asked for.
@MainActor
public final class RefreshGate {
    public init() {}
    private var running = false
    private var pending = false

    public func request(_ work: @escaping @MainActor () async -> Void) async {
        if running {
            pending = true
            return
        }
        running = true
        repeat {
            pending = false
            await work()
        } while pending
        running = false
    }
}
