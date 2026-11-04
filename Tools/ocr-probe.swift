import Foundation
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else { print("usage: ocr-probe <png>"); exit(2) }
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("cannot read image"); exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
do { try handler.perform([request]) } catch { print("ocr failed: \(error)"); exit(1) }
for observation in request.results ?? [] {
    guard let text = observation.topCandidates(1).first?.string else { continue }
    let b = observation.boundingBox
    print(String(format: "%.3f %.3f %.3f %.3f  %@", b.minX, b.minY, b.width, b.height, text))
}
