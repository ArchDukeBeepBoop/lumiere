import SwiftUI

/// Arrow-key navigation for a wall of tiles.
///
/// The app had none. One `.focusable(` existed in fifty thousand lines and it
/// was `.focusable(false)`; arrow keys did nothing in any grid, shelf or search
/// result, and every poster was reachable only with the mouse. Apple TV, Plex
/// and Infuse all drive a wall from the keyboard, and a library of this size is
/// exactly where that matters — the thing you want is four hundred tiles down.
///
/// Kept as a small state machine over an index rather than SwiftUI focus values
/// on each tile: a `LazyVGrid` only builds the rows near the viewport, so a
/// per-tile `@FocusState` cannot hold focus on a tile that has been recycled,
/// and moving down past the built window would silently lose it.
@MainActor
@Observable
public final class GridKeyboard {

    public init() {}

    /// The id of the tile the keyboard is on, or nil when the keyboard has not
    /// been used yet. Nil rather than "the first tile" so that arriving at a
    /// page does not paint a focus ring nobody asked for.
    public private(set) var focusedId: String?

    /// How many tiles sit in a row, measured from the laid-out width. The grid's
    /// columns are `.adaptive`, so nothing else in the view knows this.
    public var columns: Int = 1

    public func clear() { focusedId = nil }

    /// Puts the keyboard somewhere sensible when it is first used.
    public func begin(in ids: [String]) {
        guard focusedId == nil else { return }
        focusedId = ids.first
    }

    /// - Returns: the id to scroll to, or nil when the move went nowhere.
    @discardableResult
    public func move(_ direction: MoveCommandDirection, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current = focusedId, let index = ids.firstIndex(of: current) else {
            focusedId = ids.first
            return focusedId
        }
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -max(1, columns)
        case .down: step = max(1, columns)
        @unknown default: return nil
        }
        // Clamped, not wrapped. Wrapping a wall of four hundred tiles sends you
        // somewhere you did not ask to go, and the last row is ragged — a
        // "down" from the second-to-last row would land on nothing.
        let target = min(max(index + step, 0), ids.count - 1)
        guard target != index else { return nil }
        focusedId = ids[target]
        return focusedId
    }

    /// Columns that fit, given the room and the tile size the user chose.
    public static func columnCount(width: CGFloat, tileWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0, tileWidth > 0 else { return 1 }
        return max(1, Int((width + spacing) / (tileWidth + spacing)))
    }
}

