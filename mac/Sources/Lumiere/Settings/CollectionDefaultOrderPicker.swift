import SwiftUI
import LumiereKit

/// How a collection is ordered until you choose an order for it on its page.
struct CollectionDefaultOrderPicker: View {
    @AppStorage(Preference.collectionDefaultOrder.name) private var order
        = Preference.collectionDefaultOrder.defaultValue
    @AppStorage(Preference.hidesSingleFilmCollections.name) private var hidesSingles
        = Preference.hidesSingleFilmCollections.defaultValue

    var body: some View {
        Picker("Collections open in", selection: $order) {
            ForEach(CollectionOrder.allCases.filter { $0 != .personal }) {
                Text($0.title).tag($0.rawValue)
            }
        }
        Text("A collection you have not ordered yourself opens in this order. "
           + "Choosing one on a collection's page is remembered for that collection.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        Toggle("Hide collections of a single film", isOn: $hidesSingles)
    }
}
