import Foundation

/// Something the player did without being asked, and the way back.
///
/// Skipping an intro is the case this exists for. The app learns where an intro
/// is and jumps ninety seconds; from the viewer's side that is a picture that
/// suddenly moved, with nothing to distinguish it from a seek that misfired.
/// Saying so — briefly, with an undo — is the difference between a feature and
/// a glitch.
struct PlayerAction: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// Where the player was before it acted, so the undo is exact rather than a
    /// guess at how far it moved.
    let returnTo: Double

    static func == (a: PlayerAction, b: PlayerAction) -> Bool { a.id == b.id }
}
