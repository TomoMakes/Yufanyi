import Vision
import CoreGraphics
import Foundation

/// Swift-native Vision API (macOS 15+)의 RecognizeTextRequest를 사용한다.
/// 레거시 VNRecognizeTextRequest 대신 async/await 네이티브 API로 구현.
final class VisionOCRProvider: OCRProvider {
    private let recognitionLevel: RecognizeTextRequest.RecognitionLevel
    /// 2026-11-06 real screenshots: the correct reading (薔子, 犀鳥) was candidate #2.
    static let alternateCount = 5

    /// 실시간 번역은 반복 호출 비용 때문에 수준을 바꿔 쓸 수 있다 (측정 결과에 따름)
    init(recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate) {
        self.recognitionLevel = recognitionLevel
    }

    func recognize(image: CGImage) async throws -> OCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
        // 2026-11-06：预翻译库都是日文原文，识别语言固定为日语。
        // 自动判断语言时，汉字多的句子会被当成中文识别，假名整个丢掉
        // （例：「紅、蒼、緑、紫、無数の色が散る。」认成「紅、蒼、禄、紫、無数の色 散 。」）。
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP")]

        let observations = try await request.perform(on: image)

        let textsWithConfidence: [(String, Float)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, candidate.confidence)
        }

        if textsWithConfidence.isEmpty {
            throw OCRError.noTextFound
        }

        let text = textsWithConfidence.map(\.0).joined(separator: "\n")
        let avgConfidence = textsWithConfidence.map(\.1).reduce(0, +) / Float(textsWithConfidence.count)

        // 감지된 언어 추출 — v2에서 NLLanguageRecognizer로 보강
        let detectedLanguage: Locale.Language? = nil

        let blocks = observations.compactMap { observation -> OCRTextBlock? in
            // Same recognition pass; lower-ranked readings cost nothing extra.
            let candidates = observation.topCandidates(Self.alternateCount)
            guard let candidate = candidates.first else { return nil }
            let box = observation.boundingBox
            return OCRTextBlock(text: candidate.string, boundingBox: CGRect(
                x: box.origin.x * Double(image.width), y: box.origin.y * Double(image.height),
                width: box.width * Double(image.width), height: box.height * Double(image.height)),
                alternates: candidates.dropFirst().map(\.string).filter { $0 != candidate.string })
        }
        return OCRResult(
            text: text,
            detectedLanguage: detectedLanguage,
            confidence: avgConfidence,
            blocks: blocks
        )
    }
}

extension VisionOCRProvider {
    /// 실시간 번역용 인식기 — 초당 여러 번 부르므로 가능하면 빠른 모드를 쓴다.
    /// 2026-09-29 자막 시뮬레이터 측정: 정확 모드 CPU 48%·반응 1.25초 → 빠른 모드 27%·0.73초 (영어 자막 9/9 같은 번역).
    /// 단, 빠른 모드는 라틴 문자 몇 개 언어만 읽으므로 원문 언어가 그중 하나일 때만 쓴다 (LiveOCRPolicy).
    static func liveTranslation(sourceCode: String) -> VisionOCRProvider {
        var probe = RecognizeTextRequest()
        probe.recognitionLevel = .fast
        let fast = LiveOCRPolicy.usesFastRecognition(sourceCode: sourceCode,
                                                     fastLanguages: probe.supportedRecognitionLanguages)
        return VisionOCRProvider(recognitionLevel: fast ? .fast : .accurate)
    }
}
