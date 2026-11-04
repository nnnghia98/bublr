import AppKit
import CoreGraphics

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Bublr"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var found = 0
for w in info {
    guard let name = w[kCGWindowOwnerName as String] as? String, name.contains(owner) else { continue }
    found += 1
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    let alpha = w[kCGWindowAlpha as String] as? Double ?? -1
    let wid = w[kCGWindowNumber as String] as? Int ?? -1
    let title = w[kCGWindowName as String] as? String ?? ""
    print("wid=\(wid) layer=\(layer) alpha=\(alpha) bounds=\(bounds) title=\(title)")
}
print("total=\(found)")
