import SwiftUI

/// The per-genre tint, and the stable index behind it.
///
/// Additive, and in its own file rather than in Theme.swift, which is already at
/// the project's 300-line limit.
public extension Theme {

    /// A colour wash chosen from the genre's own name.
    ///
    /// Genre cards are drawn from library artwork, and on a library organised the
    /// way most are, several genres share their newest titles — so eight cards
    /// built from stills alone came out looking like eight versions of the same
    /// card. The mosaic fixes most of that; the tint fixes the rest, and it is the
    /// only part that still works when a genre has one poster or none.
    ///
    /// Low-alpha and appearance-aware rather than a flat colour: the wash sits on
    /// top of a photograph and its job is to make two cards distinguishable at a
    /// glance, not to become the card.
    enum Genre {

        /// Eight hues, spaced far enough apart to be told apart in peripheral
        /// vision. Not meaningful — nothing claims Horror is "the red one" — so
        /// the mapping is by name rather than by a table somebody has to maintain
        /// as servers invent genres.
        static let tints: [Color] = [
            .dynamic(light: 0x8A3B2E, dark: 0xC2543F, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x2E5E8A, dark: 0x3F7FC2, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x2E7A5C, dark: 0x3FA37D, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x6B3B8A, dark: 0x8F55B5, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x8A6E12, dark: 0xB58F26, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x1F5F63, dark: 0x2F8A90, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x8A3B63, dark: 0xB5518A, lightOpacity: 0.42, darkOpacity: 0.46),
            .dynamic(light: 0x3F4A8A, dark: 0x5A68B5, lightOpacity: 0.42, darkOpacity: 0.46),
        ]

        /// The tint for a genre.
        ///
        /// Derived from a hand-rolled fold rather than `hashValue`, which Swift
        /// seeds per process: with the standard hash, Drama would be teal this
        /// launch and violet the next, and a card whose colour moves is worse than
        /// a card with no colour at all.
        public static func tint(for name: String) -> Color {
            var accumulator: UInt64 = 5381
            for scalar in name.unicodeScalars {
                accumulator = accumulator &* 33 &+ UInt64(scalar.value)
            }
            return tints[Int(accumulator % UInt64(tints.count))]
        }
    }
}
