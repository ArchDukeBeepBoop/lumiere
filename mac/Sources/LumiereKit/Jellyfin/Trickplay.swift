import Foundation

/// Jellyfin's scrub-preview thumbnails.
///
/// The server pre-renders a grid of small frames into tile sheets: one image
/// holds `tileWidth × tileHeight` thumbnails taken every `interval`
/// milliseconds. Scrubbing to a time means working out which sheet holds that
/// frame and which cell inside it — arithmetic, not a request per frame, which
/// is what makes the preview keep up with the pointer.
public struct TrickplayInfo: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let tileWidth: Int
    public let tileHeight: Int
    public let thumbnailCount: Int
    /// Milliseconds between thumbnails.
    public let interval: Int
    public let bandwidth: Int?

    public enum CodingKeys: String, CodingKey {
        case width = "Width", height = "Height"
        case tileWidth = "TileWidth", tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount", interval = "Interval"
        case bandwidth = "Bandwidth"
    }

    public init(
        width: Int, height: Int, tileWidth: Int, tileHeight: Int,
        thumbnailCount: Int, interval: Int, bandwidth: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.thumbnailCount = thumbnailCount
        self.interval = interval
        self.bandwidth = bandwidth
    }

    public var thumbnailsPerSheet: Int {
        max(1, tileWidth * tileHeight)
    }

    /// Which pixels of a sheet hold one frame.
    ///
    /// Measured from the sheet's real dimensions rather than from `width`/`height`,
    /// because the two disagree in practice: a server that re-encoded its tiles, or
    /// a sheet whose final row is short, reports the intended frame size and stores
    /// something else. Dividing the actual pixels by the grid is the only figure
    /// that is true of the image in hand.
    ///
    /// Returns nil when the cell would fall outside the sheet, which is the shape a
    /// mismatched sheet takes — better to decline than to crop a band of the frame
    /// below.
    public func cell(
        at location: TrickplayLocation, inSheetOf sheetWidth: Int, by sheetHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        let cellWidth = sheetWidth / max(1, tileWidth)
        let cellHeight = sheetHeight / max(1, tileHeight)
        guard cellWidth > 0, cellHeight > 0 else { return nil }

        let x = location.column * cellWidth
        let y = location.row * cellHeight
        guard x >= 0, y >= 0,
              x + cellWidth <= sheetWidth, y + cellHeight <= sheetHeight else { return nil }
        return (x, y, cellWidth, cellHeight)
    }

    /// Where a given time lives: which sheet, and which cell within it.
    public func locate(seconds: Double) -> TrickplayLocation? {
        // `tileWidth > 0` belongs with the others, and its absence was a crash.
        // The two methods above already treat this value as untrusted — both wrap it
        // in `max(1, …)` — but the modulo and division below did not, and integer
        // division by zero traps in Swift rather than producing a wrong answer. A
        // server reporting `TileWidth: 0` therefore killed the app the instant the
        // pointer crossed the scrub bar, because this runs on every pointer sample.
        // Declining is the shape the rest of this file already uses for a sheet that
        // does not describe itself sensibly.
        guard interval > 0, thumbnailCount > 0, seconds >= 0, tileWidth > 0 else {
            return nil
        }

        let index = min(thumbnailCount - 1, Int(seconds * 1000) / interval)
        let sheet = index / thumbnailsPerSheet
        let offset = index % thumbnailsPerSheet

        return TrickplayLocation(
            sheetIndex: sheet,
            column: offset % tileWidth,
            row: offset / tileWidth,
            thumbnailIndex: index
        )
    }
}

public struct TrickplayLocation: Sendable, Equatable {
    public let sheetIndex: Int
    public let column: Int
    public let row: Int
    public let thumbnailIndex: Int

    /// Public so a test can name a cell directly, rather than only reaching one
    /// through `locate` and testing two things at once.
    public init(sheetIndex: Int, column: Int, row: Int, thumbnailIndex: Int) {
        self.sheetIndex = sheetIndex
        self.column = column
        self.row = row
        self.thumbnailIndex = thumbnailIndex
    }
}

extension StreamBuilder {

    /// One tile sheet. `width` must be a key the server actually generated —
    /// Jellyfin keys its trickplay data by thumbnail width.
    public static func trickplayURL(
        serverURL: URL,
        itemId: String,
        width: Int,
        sheetIndex: Int,
        mediaSourceId: String? = nil
    ) -> URL? {
        var components = URLComponents(
            url: serverURL.appendingPathComponent(
                "Videos/\(itemId)/Trickplay/\(width)/\(sheetIndex).jpg"
            ),
            resolvingAgainstBaseURL: false
        )
        if let mediaSourceId {
            components?.queryItems = [URLQueryItem(name: "mediaSourceId", value: mediaSourceId)]
        }
        return components?.url
    }
}

extension JellyfinClient {

    /// Trickplay metadata for an item, keyed by media source then by thumbnail
    /// width. Absent on servers that have not generated it, which is common —
    /// the scrubber falls back to a plain bar rather than failing.
    public func trickplay(itemId: String) async throws -> [String: [String: TrickplayInfo]] {
        struct Response: Codable, Sendable {
            let trickplay: [String: [String: TrickplayInfo]]?
            enum CodingKeys: String, CodingKey { case trickplay = "Trickplay" }
        }

        let response = try await send(
            Response.self,
            path: "Users/\(session.userId)/Items/\(itemId)",
            query: [URLQueryItem(name: "Fields", value: "Trickplay")]
        )
        return response.trickplay ?? [:]
    }
}

public extension JellyfinClient {
    /// One trickplay tile sheet, fetched through the client's own auth.
    ///
    /// Public because generating a thumbnail from a frame needs the bytes, not a
    /// URL: the sheet is a grid of frames and only one cell of it is wanted, so it
    /// has to be decoded and cropped rather than handed to an image view.
    func trickplaySheet(itemId: String, width: Int, sheetIndex: Int) async throws -> Data {
        try await sendData(path: "Videos/\(itemId)/Trickplay/\(width)/\(sheetIndex).jpg")
    }
}
