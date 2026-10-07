import Foundation
import LumiereKit

/// One place that answers "what order do libraries go in".
///
/// The home screen's shelf order is the answer, and it has to be the answer
/// everywhere: the poster row, the sidebar, and the See All pages that group
/// their rows by library. Those pages read the repository directly rather than
/// going through `AppModel`, so they were still getting the server's order while
/// the home screen used the user's — the same list in two orders, one scroll
/// apart.
///
/// A free function rather than a method on `AppModel`, because the views that
/// need it have a repository and no app.
enum LibraryOrdering {

    /// Sorts anything that carries a library id.
    ///
    /// Stable: Swift's sort is not, and libraries with no shelf of their own
    /// would otherwise swap places between launches.
    static func sorted<T>(_ items: [T], id: (T) -> String) -> [T] {
        let stored = UserDefaults.standard.string(forKey: HomeOrder.storageKey)
        let order = HomeOrder.libraryOrder(stored: stored, libraryIds: items.map(id))
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return items.enumerated()
            .sorted { left, right in
                let a = position[id(left.element)] ?? Int.max
                let b = position[id(right.element)] ?? Int.max
                return a == b ? left.offset < right.offset : a < b
            }
            .map(\.element)
    }
}
