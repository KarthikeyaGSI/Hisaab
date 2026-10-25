import Foundation
import CoreGraphics
import Vision

guard CommandLine.arguments.count == 3,
      let pdf = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL) else {
    fputs("usage: ocr_delhi_budget_scanned <pdf> <output.txt>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[2])
var pages: [String] = []
for pageNumber in 1...pdf.numberOfPages {
    guard let page = pdf.page(at: pageNumber) else { continue }
    let bounds = page.getBoxRect(.mediaBox)
    let scale: CGFloat = 2.0
    let width = Int(bounds.width * scale)
    let height = Int(bounds.height * scale)
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    context.setFillColor(CGColor.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    context.drawPDFPage(page)
    context.restoreGState()
    guard let image = context.makeImage() else { continue }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    let observations = (request.results ?? []).sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.006 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
    pages.append("--- Page \(pageNumber) ---\n" + observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
    if pageNumber % 20 == 0 { fputs("OCR pages: \(pageNumber)/\(pdf.numberOfPages)\n", stderr) }
}
try pages.joined(separator: "\n\n").write(to: output, atomically: true, encoding: .utf8)
print("pages=\(pages.count) output=\(output.path)")
