import CoreGraphics

/// The sizes the app sets type at, and the relationships between them.
///
/// In the kit rather than in the theme so the *relationships* can be checked. A
/// scale is not a list of numbers, it is a set of gaps: body 13, card title 12
/// and caption 11 is three levels inside two points, which reads as one level
/// however the weights are set. That is a fact about subtraction, and a test can
/// hold it.
///
/// The steps are roughly a fifth apart — 11, 13, 15, 18, 21, 26, 36 — which is
/// close enough to a musical scale to feel deliberate and far enough apart that
/// no two levels can be mistaken for each other at a glance.
public enum TypeScale {
    public static let caption: CGFloat = 11
    public static let cardTitle: CGFloat = 13
    public static let body: CGFloat = 15
    public static let sectionHeader: CGFloat = 18
    public static let shelfHeader: CGFloat = 23
    public static let title: CGFloat = 30
    public static let hero: CGFloat = 42
}
