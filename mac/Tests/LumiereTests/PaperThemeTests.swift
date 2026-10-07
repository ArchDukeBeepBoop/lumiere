import Foundation
import TestKit
import LumiereKit

/// Every colour in the theme has made a decision about paper.
///
/// A token added with a new light value and no paper value would fall through
/// to that light value — a cool grey panel on warm stock, noticed only by
/// someone using Paper. This reads the theme's source and holds the rule.
@MainActor
func registerPaperThemeTests(_ t: TestRunner) {
    t.suite("Paper theme") { t in
        t.test("every light colour in the theme is mapped or deliberately kept") {
            let design = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/Lumiere/Design")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: design.path)) ?? []
            let pattern = try! NSRegularExpression(pattern: #"light: 0x([0-9A-Fa-f]{6})"#)
            var undecided: [String] = []
            var seen = 0
            for file in files where file.hasPrefix("Theme") && file.hasSuffix(".swift") {
                let text = (try? String(contentsOf: design.appendingPathComponent(file), encoding: .utf8)) ?? ""
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let hex = String(text[Range(match.range(at: 1), in: text)!])
                    let value = UInt32(hex, radix: 16)!
                    seen += 1
                    if PaperTheme.ink[value] == nil && !PaperTheme.keptAsIs.contains(value) {
                        undecided.append("\(file): 0x\(hex)")
                    }
                }
            }
            t.expect(seen > 20, "read the theme's colours (\(seen))")
            t.expect(undecided.isEmpty, "no paper value for: \(undecided.joined(separator: ", "))")
        }
    }
}
