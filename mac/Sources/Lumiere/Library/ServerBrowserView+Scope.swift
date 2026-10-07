import SwiftUI
import LumiereKit

/// The scope row above a music library, and the sort control beside it.
///
/// Split from ServerBrowserView.swift for the project's 300-line rule. Not private
/// here for the same reason: the body that draws them is in that file.
extension ServerBrowserView {

    var scopePicker: some View {
        HStack(spacing: Theme.Space.md) {
            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)

            if scope == .tracks {
                Spacer(minLength: Theme.Space.sm)
                trackSortMenu
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
    }

    /// The sorts with no column of their own.
    ///
    /// Four of the six are column headings and are sorted by clicking them, which is
    /// where anyone looks first. Date Added and Plays have nowhere to be clicked —
    /// the list has no room for two more columns — so they live here, and the menu
    /// names whichever sort is active so the current order is always stated
    /// somewhere even when it is a column doing it.
    var trackSortMenu: some View {
        Menu {
            ForEach(TrackSort.allCases) { option in
                Button {
                    if trackSort == option {
                        trackSortAscending.toggle()
                    } else {
                        trackSort = option
                        trackSortAscending = option.defaultAscending
                    }
                } label: {
                    if trackSort == option {
                        Label(
                            option.title,
                            systemImage: trackSortAscending ? "chevron.up" : "chevron.down"
                        )
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Label("Sort: \(trackSort.title)", systemImage: "arrow.up.arrow.down")
                .font(Theme.Font.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
