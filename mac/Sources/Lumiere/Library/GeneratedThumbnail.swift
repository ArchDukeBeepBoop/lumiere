import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import LumiereKit

/// Replaces an episode's scraped thumbnail with a frame from the file itself.
///
/// The problem it solves is visible on any merged anime series: sixteen files that
/// the scraper matched to one listing all carry the *same* still, because the
/// listing has one still and they were all told they were that episode. Renumbering
/// them fixes the names and does nothing for the pictures — the wrong image is
/// attached to the item, and a refresh re-downloads it.
///
/// Asking Jellyfin to "extract instead" is not something the API exposes: a refresh
/// prefers a provider image where one exists, and the only way to stop that is
/// `LockData`, which freezes the entire item. So this takes the frames Jellyfin has
/// *already generated* — the trickplay tile sheets it builds for scrubbing — crops
/// one, and uploads it as the item's own image. Per-file by construction, so two
/// episodes cannot come out identical, and once uploaded it is a real image on the
/// server that every other client sees too.
///
/// The item is then frozen. That is not decoration: the scraper that attached the
/// wrong still is still configured and still scheduled, and the next image refresh
/// would put the duplicate straight back — which is the same reason the renumbering
/// locks the name. The cost is stated where it is offered, because `LockData` is the
/// only lock Jellyfin has for images and it freezes the whole item: no new cast, no
/// better synopsis, no corrected air date.
enum GeneratedThumbnail {

    enum Failure: LocalizedError {
        case noTrickplay
        case sheetUnavailable
        case cropFailed

        var errorDescription: String? {
            switch self {
            case .noTrickplay:
                return "The server has no trickplay images for this file. Turn on "
                     + "Trickplay in the server's settings and let it run, "
                     + "then try again."
            case .sheetUnavailable:
                return "The server did not return the trickplay sheet."
            case .cropFailed:
                return "The trickplay sheet could not be read as an image."
            }
        }
    }

    /// How far into the file to take the frame.
    ///
    /// Not the opening: an anime episode's first seconds are a production logo or a
    /// black frame, and a shelf of those is worse than a shelf of duplicates. A
    /// fifth of the way in is past the cold open on most things and still before
    /// anything that would spoil.
    static let position = 0.2

    /// Fetches, crops, uploads, and freezes the item so a refresh cannot undo it.
    ///
    /// - Parameter locksItem: whether to freeze. Only ever false where the caller
    ///   has already frozen the item in the same pass, since the lock is a whole
    ///   extra round trip per episode and a sweep is hundreds of them.
    @discardableResult
    static func apply(
        itemId: String,
        runtimeSeconds: Double?,
        client: JellyfinClient,
        locksItem: Bool = true
    ) async throws -> Double {
        let sources = try await client.trickplay(itemId: itemId)
        guard let widths = sources.values.first(where: { !$0.isEmpty }),
              // The largest width the server generated: this becomes a poster-sized
              // image, and trickplay tiles are small to begin with.
              let best = widths.compactMap({ key, value in Int(key).map { ($0, value) } })
                  .max(by: { $0.0 < $1.0 })
        else { throw Failure.noTrickplay }

        let info = best.1
        let seconds = (runtimeSeconds ?? 0) * position
        guard let location = info.locate(seconds: seconds)
                ?? info.locate(seconds: 0) else { throw Failure.noTrickplay }

        // Through the client rather than a bare URLSession: the sheet endpoint is
        // authenticated like everything else, and a second place that builds auth
        // headers is a second place for them to be built wrong.
        guard let data = try? await client.trickplaySheet(
            itemId: itemId, width: best.0, sheetIndex: location.sheetIndex
        ) else { throw Failure.sheetUnavailable }

        let jpeg = try crop(sheet: data, at: location, info: info)
        try await client.uploadImage(
            itemId: itemId, type: "Primary", data: jpeg, mimeType: "image/jpeg"
        )

        // After the upload, never before. Freezing first would leave an item frozen
        // for a thumbnail that then failed to arrive — and on a server with no
        // trickplay data that is every episode in the sweep.
        if locksItem {
            try await client.updateItem(itemId: itemId, edit: ItemEdit(lockAll: true))
        }
        return seconds
    }

    /// Cuts one cell out of a tile sheet and re-encodes it.
    static func crop(sheet: Data, at location: TrickplayLocation, info: TrickplayInfo) throws -> Data {
        guard let source = CGImageSourceCreateWithData(sheet as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.cropFailed }

        guard let cell = info.cell(
            at: location, inSheetOf: image.width, by: image.height
        ), let cropped = image.cropping(to: CGRect(
            x: cell.x, y: cell.y, width: cell.width, height: cell.height
        )) else { throw Failure.cropFailed }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw Failure.cropFailed }
        CGImageDestinationAddImage(
            destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw Failure.cropFailed }
        return output as Data
    }
}
