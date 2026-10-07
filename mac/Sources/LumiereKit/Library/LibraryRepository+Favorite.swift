import Foundation
import GRDB

/// Split from LibraryRepository+WatchState.swift for the 300-line limit.
extension LibraryRepository {

    @discardableResult
    public func setFavorite(itemId: String, favorite: Bool) async -> Bool {
        let previous = try? await entry(id: itemId)
        await applyLocalFavorite(itemId: itemId, favorite: favorite)

        do {
            try await client.markFavorite(itemId: itemId, favorite: favorite)
            return true
        } catch {
            if ConnectionState.isUnreachable(error) {
                await enqueueWrite(itemId: itemId, kind: .favorite, value: favorite)
                return true
            }
            await applyLocalFavorite(
                itemId: itemId,
                favorite: previous?.userData?.isFavorite ?? false
            )
            return false
        }
    }
}
