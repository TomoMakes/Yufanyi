import CoreGraphics
import Foundation

/// OCR 인식 결과.
nonisolated struct OCRResult: Sendable {
    /// 인식된 텍스트
    let text: String
    /// 감지된 소스 언어 (번역 Provider에 전달)
    let detectedLanguage: Locale.Language?
    /// 인식 신뢰도 (0.0 ~ 1.0)
    let confidence: Float
    /// Vision observations in reading order; coordinates use the lower-left origin.
    let blocks: [OCRTextBlock]

    init(text: String, detectedLanguage: Locale.Language?, confidence: Float,
         blocks: [OCRTextBlock] = []) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.confidence = confidence
        self.blocks = blocks
    }

    /// Keep soft wraps separate from spatial paragraph boundaries for Luna only.
    var dialogueText: String {
        guard !blocks.isEmpty else { return text }
        let cleaned = Self.dialogueBlocks(blocks)
        guard !cleaned.isEmpty else { return text }
        let blocks = Self.horizontalReadingOrder(cleaned)
        var result = blocks[0].text
        for index in blocks.indices.dropFirst() {
            let previous = blocks[index - 1].boundingBox
            let current = blocks[index].boundingBox
            let height = max(previous.height, current.height)
            let verticalGap = previous.minY - current.maxY
            let horizontalOverlap = min(previous.maxX, current.maxX) - max(previous.minX, current.minX)
            let sameRow = abs(previous.midY - current.midY) < height * 0.5
            let separateColumn = horizontalOverlap < -height * 2.5
            let next = blocks[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousText = blocks[index - 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let startsQuote = next.first == "「" || next.first == "『"
            let speakerLabel = previousText.count <= 20
                && !previousText.contains(where: { "。！？.!?「」『』".contains($0) }) && startsQuote
            let openQuotes = result.filter { "「『".contains($0) }.count
                - result.filter { "」』".contains($0) }.count
            let continuesQuote = openQuotes > 0 && next.first != "「"
            let paragraph = (verticalGap > height * 0.9 || separateColumn)
                && !speakerLabel && !continuesQuote
            result += paragraph ? "\n\n" : (sameRow ? " " : "\n")
            result += blocks[index].text
        }
        return result
    }

    /// Lower-ranked Vision readings keyed by the line text that appears in
    /// `dialogueText`. Luna tries them only after the primary reading misses.
    var dialogueAlternates: [String: [String]] {
        var result: [String: [String]] = [:]
        for block in Self.dialogueBlocks(blocks) where !block.alternates.isEmpty {
            let key = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            for alternate in block.alternates {
                let value = alternate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, value != key, !(result[key]?.contains(value) ?? false) {
                    result[key, default: []].append(value)
                }
            }
        }
        return result
    }

    /// Blocks Luna reads: noise removed, then one row split by Vision glued back.
    static func dialogueBlocks(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        mergedSameRowBlocks(cleanedDialogueBlocks(blocks))
    }

    private static let joinDashes = Set("―─—–-")
    private static let vowelDashes = Set("ー一")

    /// Real screenshot 2026-11-06: Vision split 薔子さんと───そのすぐ後ろに… at the dash run
    /// into 「薔子さんと-」 and 「そのすぐ後ろに…」, then returned the second row between
    /// them. Glue two blocks of one row left to right when nothing else lies between
    /// them and either the gap is small (a plain split) or a dash remnant sits at the
    /// cut (ー/一 count only across a gap wider than 1.5 line heights, so a plain split
    /// right after 「スーパー」 keeps its long vowel).
    /// The remnant becomes a two-dash run, which Luna's loose key folds like ───.
    static func mergedSameRowBlocks(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = blocks
        var changed = true
        while changed {
            changed = false
            search: for i in result.indices {
                for j in result.indices where j != i {
                    let lb = result[i].boundingBox, rb = result[j].boundingBox
                    let low = min(lb.height, rb.height), high = max(lb.height, rb.height)
                    guard low > 0, high <= low * 1.4, isHorizontal(lb), isHorizontal(rb),
                          abs(lb.midY - rb.midY) < low * 0.5,
                          lb.maxX <= rb.minX + low * 0.3 else { continue }
                    let left = trimmed(result[i].text), right = trimmed(result[j].text)
                    guard letterCount(left) >= 1, letterCount(right) >= 1 else { continue }
                    let gap = rb.minX - lb.maxX
                    let wide = gap > low * 1.5
                    func isDash(_ c: Character?) -> Bool {
                        guard let c else { return false }
                        return joinDashes.contains(c) || (wide && vowelDashes.contains(c))
                    }
                    let dashCut = isDash(left.last) || isDash(right.first)
                    guard gap <= low * (dashCut ? 6 : 1.5) else { continue }
                    let between = result.indices.contains { k in
                        guard k != i, k != j else { return false }
                        let kb = result[k].boundingBox
                        return abs(kb.midY - lb.midY) < low * 0.5 && kb.midX > lb.maxX && kb.midX < rb.minX
                    }
                    guard !between else { continue }
                    func join(_ a: String, _ b: String) -> String {
                        guard dashCut else { return a + b }
                        var a = a, b = b
                        while isDash(a.last) { a.removeLast() }
                        while isDash(b.first) { b.removeFirst() }
                        return a + "――" + b
                    }
                    let alternates = result[i].alternates.map { join(trimmed($0), right) }
                        + result[j].alternates.map { join(left, trimmed($0)) }
                    result[i] = OCRTextBlock(text: join(left, right), boundingBox: lb.union(rb), alternates: alternates)
                    result.remove(at: j)
                    changed = true
                    break search
                }
            }
        }
        return result
    }

    private static let dialoguePunctuation = "「」『』（）()。、！？!?…‥・"

    private static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }

    private static func isHorizontal(_ box: CGRect) -> Bool {
        box.width > 0 && box.height > 0 && box.height <= box.width * 1.5
    }

    /// Real-screenshot cleanup (2026-11-06), applied only when at least one block
    /// looks like dialogue. Removes furigana, UI buttons and background signs that
    /// sit outside the dialogue column, and glues a symbol-only fragment (e.g. an
    /// opening 「……─── split off by Vision) to the dialogue on the same row.
    static func cleanedDialogueBlocks(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        func trimmed(_ b: OCRTextBlock) -> String { b.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        func punctuated(_ b: OCRTextBlock) -> Bool { trimmed(b).contains(where: { dialoguePunctuation.contains($0) }) }
        let dialogue = blocks.filter { punctuated($0) && letterCount(trimmed($0)) >= 2 && isHorizontal($0.boundingBox) }
        guard !dialogue.isEmpty else { return blocks }
        let columnMax = dialogue.map(\.boundingBox.maxX).max()!
        let heights = dialogue.map(\.boundingBox.height).sorted()
        let typical = heights[heights.count / 2]

        var kept = blocks.filter { block in
            let text = trimmed(block), box = block.boundingBox
            if text.isEmpty { return false }
            if punctuated(block) { return true }
            let kanaOnly = text.range(of: "^[\\p{Hiragana}\\p{Katakana}ー]+$", options: .regularExpression) != nil
            // Furigana: small kana directly above a dialogue line that it overlaps horizontally.
            if kanaOnly && box.height < typical * 0.65, dialogue.contains(where: { d in
                let db = d.boundingBox
                return box.minY >= db.midY && box.minY - db.maxY < typical
                    && min(box.maxX, db.maxX) > max(box.minX, db.minX)
            }) { return false }
            let letters = letterCount(text)
            // Short label entirely to the right of the dialogue column (auto/skip buttons,
            // signs). The left side is left alone: a framed name label lives there.
            if letters <= 6 && box.minX > columnMax { return false }
            // Vertical sign inside a horizontal dialogue frame.
            if !isHorizontal(box) && letters <= 8 { return false }
            // Single stray glyph that is not punctuation (background texture).
            if letters <= 1 && !punctuated(block) && !dialogue.contains(where: { d in
                abs(d.boundingBox.midY - box.midY) < max(d.boundingBox.height, box.height) * 0.5
            }) { return false }
            return true
        }

        // Merge symbol-only fragments into the dialogue block on the same row.
        var index = 0
        while index < kept.count {
            let fragment = kept[index]
            let text = trimmed(fragment)
            guard letterCount(text) == 0, punctuated(fragment) else { index += 1; continue }
            let box = fragment.boundingBox
            let partner = kept.indices.filter { $0 != index }.filter { other in
                let ob = kept[other].boundingBox
                return letterCount(trimmed(kept[other])) >= 2
                    && abs(ob.midY - box.midY) < min(ob.height, box.height) * 0.6
                    && (box.maxX <= ob.minX + ob.height || box.minX >= ob.maxX - ob.height)
            }.min { a, b in
                abs(kept[a].boundingBox.midX - box.midX) < abs(kept[b].boundingBox.midX - box.midX)
            }
            guard let other = partner else { index += 1; continue }
            let target = kept[other]
            let before = box.midX < target.boundingBox.midX
            let mergedText = before ? text + target.text : target.text + text
            kept[other] = OCRTextBlock(text: mergedText, boundingBox: target.boundingBox.union(box),
                                       alternates: target.alternates.map { before ? text + $0 : $0 + text })
            kept.remove(at: index)
        }
        return kept
    }

    /// Vision can return a short final line before the longer lines above it.
    /// Reorder only clearly horizontal, single-column observations. Independent
    /// columns, vertical text, and overlapping observations retain engine order.
    private static func horizontalReadingOrder(_ blocks: [OCRTextBlock]) -> [OCRTextBlock] {
        guard blocks.count > 1 else { return blocks }
        let boxes = blocks.map(\.boundingBox)
        guard boxes.allSatisfy({ box in
            box.minX.isFinite && box.minY.isFinite && box.width.isFinite && box.height.isFinite
                && box.width > 0 && box.height > 0 && box.height <= box.width * 1.5
        }), let left = boxes.map(\.minX).max(), let right = boxes.map(\.maxX).min(),
              left < right else { return blocks }

        let ordered = blocks.enumerated().sorted {
            if $0.element.boundingBox.midY == $1.element.boundingBox.midY { return $0.offset < $1.offset }
            return $0.element.boundingBox.midY > $1.element.boundingBox.midY
        }.map(\.element)
        for index in ordered.indices.dropFirst() {
            let upper = ordered[index - 1].boundingBox, lower = ordered[index].boundingBox
            guard upper.minY - lower.maxY >= -min(upper.height, lower.height) * 0.25 else { return blocks }
        }
        return ordered
    }
}

nonisolated struct OCRTextBlock: Sendable {
    let text: String
    /// Pixel coordinates so horizontal and vertical distances have the same scale.
    let boundingBox: CGRect
    /// Vision's lower-ranked readings of the same line (2026-11-06). Language
    /// correction can drop a rare kanji (薔子 → 子) while keeping the right reading
    /// as the second candidate. Luna consults these only after a miss.
    var alternates: [String] = []
}

/// OCR 처리를 담당하는 Provider 프로토콜.
/// 새로운 OCR 엔진(Tesseract, 커스텀 ML 등)은 이 프로토콜을 채택하면 된다.
protocol OCRProvider: Sendable {
    func recognize(image: CGImage) async throws -> OCRResult
}

nonisolated enum OCRError: LocalizedError {
    case noTextFound
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return L10n.noTextFound
        case .recognitionFailed(let reason):
            return L10n.ocrFailed(reason)
        }
    }
}
