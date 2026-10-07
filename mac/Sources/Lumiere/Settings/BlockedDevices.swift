import SwiftUI
import LumiereKit

/// Devices on the home network the server refuses outright — not even the
/// sign-in screen. By address, so a device that changes address on the
/// router has to be blocked again; the note says so.
struct BlockedDevices: View {
    let addresses: [String]
    let onChange: ([String]) -> Void
    @State private var draft = ""

    var body: some View {
        ForEach(addresses, id: \.self) { address in
            HStack {
                Label(address, systemImage: "nosign")
                Spacer()
                Button("Unblock") { onChange(addresses.filter { $0 != address }) }
                    .font(Theme.Font.caption)
            }
        }
        HStack {
            TextField("Block a device by address, e.g. 192.168.50.19", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("Block", action: add).disabled(!Self.isAddress(draft))
        }
        Text("A blocked device cannot reach the server at all, sign-in included. "
           + "If your router gives it a new address, block that one too.")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func add() {
        let address = draft.trimmingCharacters(in: .whitespaces)
        guard Self.isAddress(address), !addresses.contains(address) else { return }
        onChange(addresses + [address])
        draft = ""
    }

    static func isAddress(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
