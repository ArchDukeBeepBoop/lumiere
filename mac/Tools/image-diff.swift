// image-diff <a.png> <b.png> [threshold%]
//
// How different two screenshots are, as the mean per-pixel difference in
// percent after both are reduced to 256 wide — enough to see a missing panel,
// a colour gone wrong or text that moved, and blind to anti-aliasing noise.
// Exit 0 within the threshold (default 3%), 3 over it.
import CoreGraphics
import Foundation
import ImageIO

func pixels(_ path: String, _ w: Int, _ h: Int) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return data
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: image-diff a.png b.png [threshold%]"); exit(1) }
let threshold = args.count > 3 ? Double(args[3]) ?? 3 : 3
let w = 256, h = 145
guard let a = pixels(args[1], w, h), let b = pixels(args[2], w, h) else { print("unreadable"); exit(1) }
var total = 0.0
for i in stride(from: 0, to: a.count, by: 4) {
    for c in 0..<3 { total += abs(Double(a[i + c]) - Double(b[i + c])) }
}
let percent = total / Double(w * h * 3) / 255 * 100
print(String(format: "%.2f%% different", percent))
exit(percent > threshold ? 3 : 0)
