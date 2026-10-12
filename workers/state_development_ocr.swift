// Local, read-only OCR of preserved report-page images. No network or publication.
import Foundation
import Vision
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: state_development_ocr image output.json\n", stderr)
    exit(2)
}
do {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]), options: [:])
    try handler.perform([request])
    let rows: [[String: Any]] = (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        return ["text": text.string, "confidence": text.confidence,
                "x": box.minX, "y": box.minY, "width": box.width, "height": box.height]
    }
    let data = try JSONSerialization.data(withJSONObject: ["engine": "Apple Vision accurate en-US",
        "usesLanguageCorrection": false, "reviewStatus": "ocr_unverified", "rows": rows], options: [.prettyPrinted, .sortedKeys])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    try data.write(to: output, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
} catch {
    fputs("OCR failed: \(error)\n", stderr)
    exit(1)
}
