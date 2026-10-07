import SwiftUI

/// The home screen's one sentence of news. See `HomeModel.newsLine`.
struct HomeNewsLine: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Space.shelfInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
