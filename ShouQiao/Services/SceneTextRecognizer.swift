import Foundation
import UIKit
import Vision

final class SceneTextRecognizer {
    private let queue = DispatchQueue(label: "org.signbridge.ocr")

    func recognize(
        image: UIImage,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            completion(.failure(NSError(
                domain: "ShouQiao.OCR",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法读取画面"]
            )))
            return
        }

        queue.async {
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                DispatchQueue.main.async { completion(.success(text)) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
