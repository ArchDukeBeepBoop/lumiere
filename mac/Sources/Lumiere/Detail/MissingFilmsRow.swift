import SwiftUI
import LumiereKit

/// The films of a collection's series that are not in the library, drawn in
/// the collection as outlines where their posters would be — so "3 of 6" is
/// something you can see, and know what to look for.
struct MissingFilmsRow: View {
    let repository: LibraryRepository
    let collectionId: String

    @State private var missing: [String] = []

    var body: some View {
        Group {
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Not in your library")
                        .font(Theme.Font.shelfTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.horizontal, Theme.Space.shelfInset)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.md) {
                            ForEach(missing, id: \.self) { tile($0) }
                        }
                        .padding(.horizontal, Theme.Space.shelfInset)
                    }
                }
            }
        }
        .task(id: collectionId) { missing = await repository.missingFilms(collectionId: collectionId) }
    }

    private func tile(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.Palette.textDisabled, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: Theme.Art.shelfPosterWidth * 0.7, height: Theme.Art.shelfPosterWidth * 1.05)
            .overlay {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Space.sm)
            }
    }
}
