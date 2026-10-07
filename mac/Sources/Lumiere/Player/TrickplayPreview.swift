import SwiftUI
import LumiereKit

/// The frame that follows the pointer along the scrubber.
///
/// A card rather than a thumbnail with a chip under it: image and timecode share
/// one surface, one corner radius and one edge, so the thing floating over the
/// film reads as a single object. Where the server ships no trickplay sheets the
/// card is just the timecode, which is still the answer to "where am I dragging to".
///
/// The server ships a grid of frames per image, so this loads one sheet and shows
/// a single cell out of it by scaling up and offsetting — no request per frame,
/// which is what lets the preview keep up with a drag.
struct TrickplayPreview: View {
    let model: PlayerModel
    let serverURL: URL
    let pipeline: ImagePipeline
    let itemId: String
    let seconds: Double
    /// A fixed size, for a chapter's picture; otherwise the scrubbing size.
    var fixedWidth: CGFloat? = nil

    private var previewWidth: CGFloat { fixedWidth ?? Theme.PlayerMetric.trickplayWidth(playing: model.isPlaying) }

    var body: some View {
        VStack(spacing: 0) {
            if let info = model.trickplay,
               let width = model.trickplayWidth,
               let location = info.locate(seconds: seconds),
               let request = sheetRequest(info: info, width: width, sheet: location.sheetIndex) {
                sheetCell(info: info, location: location, request: request)
                Divider().overlay(Theme.PlayerPalette.surfaceStroke)
            }

            // The chapter under the pointer, named, where the file names its
            // chapters: the ticks on the bar said where, never what.
            Text(chapterName.map { "\(PlayerModel.timecode(seconds))  ·  \($0)" }
                 ?? PlayerModel.timecode(seconds))
                .lineLimit(1)
                .truncationMode(.tail)
                .font(Theme.Font.trickplayTimecode)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                // Only when there is a still to centre it under.
                //
                // Without one the card has no width of its own, so `maxWidth:
                // .infinity` took the whole *scrub bar* — a full-width dark slab
                // sitting directly above the bar, which reads as a second seek bar
                // superimposed on the first. It appeared on hover, on any server
                // with no trickplay images, which is most of them.
                .frame(maxWidth: hasSheet ? .infinity : nil)
        }
        .frame(width: hasSheet ? previewWidth : nil)
        .background(Theme.PlayerPalette.surfaceBottom)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.trickplay, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.trickplay, style: .continuous)
                .strokeBorder(Theme.PlayerPalette.surfaceStroke, lineWidth: 1)
        }
        // One card on screen at a time, so a single shadow is what lifts it off a
        // bright frame rather than a cost paid per element.
        .shadow(
            color: Theme.PlayerPalette.surfaceShadow,
            radius: Theme.PlayerMetric.surfaceShadow,
            y: Theme.PlayerMetric.surfaceShadowY
        )
        .allowsHitTesting(false)
    }

    /// The named chapter at this point, or nil — files with "Chapter 3" for
    /// every name say nothing a timecode does not.
    private var chapterName: String? {
        guard let chapter = model.chapters.last(where: { $0.startSeconds <= seconds + 0.5 }),
              let name = chapter.name, !name.isEmpty,
              name.range(of: #"^(chapter\s*)?\d+$"#, options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        return name
    }

    /// Whether there is an image to size the card to. Without one the card shrinks
    /// to the timecode rather than leaving a 208pt empty box hanging over the film.
    private var hasSheet: Bool {
        model.trickplay != nil && model.trickplayWidth != nil
            && model.trickplay?.locate(seconds: seconds) != nil
    }

    /// One cell, cropped out of the sheet.
    ///
    /// The sheet is drawn at `tileWidth × tileHeight` times the cell size and
    /// then offset so the wanted cell lands in the visible window — the cheapest
    /// way to crop an image in SwiftUI without re-decoding it per frame.
    private func sheetCell(
        info: TrickplayInfo,
        location: TrickplayLocation,
        request: ImageRequest
    ) -> some View {
        let cellHeight = previewWidth * CGFloat(info.height) / CGFloat(max(1, info.width))

        return RemoteImage(request: request, pipeline: pipeline, contentMode: .fill)
            .frame(
                width: previewWidth * CGFloat(info.tileWidth),
                height: cellHeight * CGFloat(info.tileHeight)
            )
            .offset(
                x: -previewWidth * CGFloat(location.column),
                y: -cellHeight * CGFloat(location.row)
            )
            .frame(width: previewWidth, height: cellHeight, alignment: .topLeading)
            .clipped()
    }

    /// Sheets are fetched through the same bounded pipeline as artwork, so a long
    /// scrub cannot grow memory without limit — it evicts like everything else.
    private func sheetRequest(info: TrickplayInfo, width: Int, sheet: Int) -> ImageRequest? {
        guard let url = StreamBuilder.trickplayURL(
            serverURL: serverURL, itemId: itemId, width: width, sheetIndex: sheet
        ) else { return nil }

        let sheetPixelWidth = width * info.tileWidth
        return ImageRequest(
            explicitURL: url,
            cacheKey: "trickplay|\(itemId)|\(width)|\(sheet)",
            displayWidth: CGFloat(sheetPixelWidth),
            aspectRatio: CGFloat(info.tileWidth * info.width)
                / CGFloat(max(1, info.tileHeight * info.height)),
            screenScale: 1
        )
    }
}
