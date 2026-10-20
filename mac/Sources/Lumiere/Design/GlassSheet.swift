import SwiftUI

extension View {
    /// A sheet on glass, as macOS's own sheets and Apple TV's panels are:
    /// the window behind shows through, frosted, with a wash of the page
    /// colour so text stays legible in both appearances. Forms and lists
    /// inside drop their own opaque backgrounds so the glass reaches them.
    func glassSheet() -> some View {
        scrollContentBackground(.hidden)
            .presentationBackground {
                GlassFill(shape: Rectangle(), material: .regularMaterial,
                          tint: Theme.Palette.canvas.opacity(0.55))
            }
    }
}
