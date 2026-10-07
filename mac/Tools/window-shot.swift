// window-shot <pid> <out.png>
//
// Captures one process's main window — its own pixels, never whatever else is
// on screen — and says whether it has content. Exit 0 with content, 2 when the
// area under the navigation bar is one flat colour (an app that launched but
// drew nothing), 1 when there is no window.
//
// Built for the walkthrough and the memory script: a demo run that silently
// showed an empty window once made both of them report success.
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count == 3, let pid = Int32(args[1]) else {
    FileHandle.standardError.write("usage: window-shot <pid> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    .compactMap { info -> (Int, Double)? in
        guard let id = info[kCGWindowNumber as String] as? Int,
              let b = info[kCGWindowBounds as String] as? [String: Double],
              let w = b["Width"], let h = b["Height"], h > 300 else { return nil }
        return (id, w * h)
    }
    .sorted { $0.1 > $1.1 }
guard let window = windows.first?.0 else { print("no window"); exit(1) }

let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l\(window)", args[2]]
try capture.run()
capture.waitUntilExit()

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("unreadable"); exit(1) }
let width = 64, height = 64
var pixels = [UInt8](repeating: 0, count: width * height)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
// The lower 85%: below the title bar and the navigation bar, which draw even
// when nothing else does.
let rows = pixels[0..<(width * height * 85 / 100)].map(Double.init)
let mean = rows.reduce(0, +) / Double(rows.count)
let spread = (rows.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(rows.count)).squareRoot()
print(String(format: "window %d, content spread %.1f", window, spread))
exit(spread < 3 ? 2 : 0)
