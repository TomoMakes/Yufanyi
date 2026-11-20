import Foundation
import SQLite3

/// Read-only LunaTranslator SQLite reader for ScreenTranslate Live Translate.
/// Layout-aware paragraph matching: exact, dialogue-only exact, conservative fuzzy.
/// It does not call any machine-translation provider.
final class LunaPretranslationProvider: TranslationProvider {
    let name = "Luna 预翻译"
    let requiresAPIKey = false

    private let databasePath: String
    private struct Entry {
        let key: String
        let strictKey: String
        let id: Int64
        let strictLength: Int
        let translation: String
    }
    private var rows: [Entry]?
    private var exact: [String: String] = [:]
    private var ambiguousExact = Set<String>()
    private var looseExact: [String: String] = [:]
    private var ambiguousLoose = Set<String>()
    private var anchors: [String: [Int]] = [:]
    private var repairIndex: [String: [Int]] = [:]
    private var exactPositions: [String: [Int64]] = [:]
    private var loosePositions: [String: [Int64]] = [:]
    /// 2026-11-14: translations of every record sharing a key once trailing punctuation is dropped
    private var stemIndex: [String: Set<String>] = [:]
    /// Row indices by loose-key length (short-line one-edit rule)
    private var lengthBuckets: [Int: [Int]] = [:]
    private let contextEnabled: Bool
    /// Settings, default off: try swapping one look-alike character (see lookAlikeMatch)
    private let lookAlikeEnabled: Bool
    private var lastExactID: Int64?
    private var reliableRun = 0
    private var consecutiveMisses = 0
    private var contextUsed = false
    private let contextWindow: Int64 = 8

    func resetContext() {
        lastExactID = nil
        reliableRun = 0
        consecutiveMisses = 0
    }

    init(path: String, contextEnabled: Bool = true, lookAlikeEnabled: Bool = false) {
        databasePath = path
        self.contextEnabled = contextEnabled
        self.lookAlikeEnabled = lookAlikeEnabled
    }

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        try translate(text: text, lineAlternates: [:])
    }

    /// `lineAlternates`: Vision's lower-ranked readings keyed by a line of `text`
    /// (OCRResult.dialogueAlternates). Synchronous so the per-call state below
    /// cannot interleave with another call.
    /// `isRescue`: a second reading of the same frame (another image treatment). A miss
    /// here must not count towards the consecutive misses that reset the context.
    ///
    /// Returns "" when nothing matched and the text holds no Japanese at all (2026-11-14):
    /// a symbol-only line read as letters (「！？」 → TLI), an emulator overlay, a desktop.
    /// There is nothing to translate, so it is neither shown nor counted as a miss.
    func translate(text: String, lineAlternates: [String: [String]], isRescue: Bool = false) throws -> String {
        if rows == nil { try loadDatabase() }
        self.lineAlternates = lineAlternates
        defer { self.lineAlternates = [:] }
        contextUsed = false
        // A complete database record wins even when OCR wrapped it or inserted a large gap.
        if let translation = exact[Self.normalized(text)] { return renderMatch(text, translation) }
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\n[ \\t]*\\n(?:[ \\t]*\\n)*", with: "\u{2029}", options: .regularExpression)
            .components(separatedBy: "\u{2029}")
        let output = paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .flatMap { paragraph -> [String] in
                translateParagraph(paragraph).filter { !Self.isForeignMiss($0) }
            }.joined(separator: "\n\n")
        if output.contains("［预翻译未命中］"), !isRescue {
            consecutiveMisses += 1
            if consecutiveMisses >= 2 { resetContext() }
        }
        return output
    }

    private static let missPrefix = "［预翻译未命中］\n"

    nonisolated static func hasJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3041...0x3096, 0x30A1...0x30FA, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3005: return true
            default: return false
            }
        }
    }

    /// An unmatched segment without a single kana or kanji.
    private static func isForeignMiss(_ segment: String) -> Bool {
        segment.hasPrefix(missPrefix) && !hasJapanese(String(segment.dropFirst(missPrefix.count)))
    }

    /// Live shortcut (2026-11-06): on AUTO a short line can leave the screen before two
    /// identical frames (~0.6 s apart) confirm it, so it is never shown. A frame whose whole
    /// text is one complete deterministic record - ends with a closing quote or sentence-final
    /// mark (or a closing quote whose opening quote was dropped by OCR), and matches an
    /// unambiguous database record without fuzzy/context guesswork - may be shown at once.
    /// A half-typed turn lacks its closing mark or has an unclosed opening quote and keeps
    /// waiting. Never loads the database (the first translation does), so it cannot block a frame.
    func isCompleteExactHit(_ text: String, lineAlternates: [String: [String]] = [:]) -> Bool {
        guard rows != nil else { return false }
        let key = Self.normalized(text)
        guard let last = key.last, "」』）)。！？!?…".contains(last),
              key.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        if queryVariants(text).contains(where: { ambiguousExact.contains($0) }) { return false }
        if Self.balanced(key) {
            if exactMatch(text) != nil
                || longVowelMatch(text) != nil
                || ellipsisSokuonMatch(text) != nil
                || smallKanaMatch(text) != nil
                || leadingSymbolMatch(text) != nil
                || leadingDashMatch(text) != nil
                || dashDroppedMatch(text) != nil
                || droppedStraightQuoteMatch(text) != nil
                || quotedPhraseMatch(text) != nil
                || angleBracketMatch(text) != nil
                || (last != "…" && tailMatch(text) != nil)
                || translateSeparatedPrefix(text) != nil {
                return true
            }
            if !lineAlternates.isEmpty {
                self.lineAlternates = lineAlternates
                defer { self.lineAlternates = [:] }
                if alternateMatch(text) != nil { return true }
            }
            return false
        }
        guard "」』）".contains(last), !Self.hasUnclosedOpening(key) else { return false }
        return leadingSymbolMatch(text) != nil || edgeQuoteMatch(text) != nil || angleBracketMatch(text) != nil
    }

    private func exactMatch(_ text: String) -> String? {
        for query in queryVariants(text) {
            if ambiguousExact.contains(query) { return nil }
            if let translation = exact[query], !translation.isEmpty { return translation }
        }
        // Relaxed punctuation must not turn a truncated/open turn into a complete record.
        var closings: [Character] = []
        for c in text {
            if let close = [Character("「"): Character("」"), "『": "』", "（": "）", "(": ")"][c] { closings.append(close) }
            else if closings.last == c { closings.removeLast() }
        }
        guard closings.isEmpty else { return nil }
        for query in queryVariants(text).map(Self.looseKey) {
            if ambiguousLoose.contains(query) { continue }
            if let translation = looseExact[query] { return translation }
        }
        return nil
    }

    private func translateParagraph(_ text: String) -> [String] {
        if let translation = lookup(text) { return [renderMatch(text, translation)] }
        if let separated = translateSeparatedPrefix(text) { return separated }
        let units = Self.dialogueUnits(text)
        guard units.count > 1 else { return [matchOrOriginal(text)] }

        // Resolve spans, not individual OCR lines. Longest exact records are preferred;
        // unmatched spans are retained and cannot cancel translations of other spans.
        var output: [String] = []
        var pending: [String] = []
        func flush() {
            guard !pending.isEmpty else { return }
            output.append(matchOrOriginal(pending.joined(separator: "\n")))
            pending.removeAll()
        }
        var start = 0
        while start < units.count {
            var matchedEnd: Int?
            for end in stride(from: units.count, through: start + 1, by: -1) {
                if let translation = exactMatch(units[start..<end].joined(separator: "\n")) {
                    flush()
                    output.append(renderMatch(units[start..<end].joined(separator: "\n"), translation))
                    matchedEnd = end
                    break
                }
            }
            if let end = matchedEnd {
                start = end
            } else {
                pending.append(units[start])
                // Only a closed quotation turn is an unconditional textual boundary.
                // Unquoted sentence endings alone may belong to one multi-sentence record.
                if Self.isClosedTurn(units[start]) { flush() }
                start += 1
            }
        }
        flush()
        return output
    }

    /// A separate short first line can be a speaker or narrative, even when the
    /// following record has no quotation marks. Translate only a complete, exact
    /// suffix and keep the first line visible; never guess that it is a name.
    private func translateSeparatedPrefix(_ text: String) -> [String]? {
        guard !ambiguousExact.contains(Self.normalized(text)),
              let newline = text.firstIndex(of: "\n") else { return nil }
        let prefix = String(text[..<newline]).precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hiraganaRuby = prefix.count <= 8
            && prefix.range(of: "^[\\p{Hiragana}ー]+$", options: .regularExpression) != nil
        let nonHiraganaName = prefix.count <= 10
            && prefix.range(of: "^[\\p{Han}\\p{Katakana}A-Za-z0-9ー・]+$", options: .regularExpression) != nil
        guard !prefix.isEmpty,
              hiraganaRuby || nonHiraganaName
                || (prefix.count <= 4 && prefix.range(of: "^[\\p{L}\\p{N}ー・]+$", options: .regularExpression) != nil)
        else { return nil }
        let body = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyKey = Self.normalized(body)
        let bodyLetters = bodyKey.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard bodyLetters >= 8, !ambiguousExact.contains(bodyKey) else { return nil }
        let translation: String?
        if let hit = exact[bodyKey] {
            translation = hit
        } else if !hiraganaRuby, let last = bodyKey.last, "」』）)".contains(last) {
            translation = exactMatch(body) ?? leadingSymbolMatch(body) ?? dashDroppedMatch(body) ?? edgeQuoteMatch(body)
        } else {
            translation = nil
        }
        guard let translation else { return nil }

        let prefixKey = Self.normalized(prefix)
        let leading: String
        if ambiguousExact.contains(prefixKey) {
            leading = "［预翻译未命中］\n" + prefix
        } else if let known = exact[prefixKey] {
            leading = renderMatch(prefix, known)
        } else {
            leading = "［原文前缀］\n" + prefix
        }
        return [leading, renderMatch(body, translation)]
    }

    private func matchOrOriginal(_ text: String) -> String {
        if queryVariants(text).contains(where: { ambiguousExact.contains($0) }) {
            return "［预翻译未命中］\n" + text
        }
        if let translation = lookup(text) { return renderMatch(text, translation) }
        if let (reading, translation) = alternateMatch(text) { return renderMatch(reading, translation) }
        if let translation = splitMatch(text) { return translation }
        return "［预翻译未命中］\n" + text
    }

    private var lineAlternates: [String: [String]] = [:]

    // Real screenshot 2026-11-06: Vision's language correction dropped the rare kanji
    // in 薔子 (やっぱり子さん) although its second candidate was right; 314 records of the
    // 天秤 database contain 薔. After a miss only, swap one OCR line for one of Vision's
    // own lower-ranked readings and accept an exact (strict/loose) record. Guards:
    // the reading restores or replaces characters (never shorter, at most 2 edits),
    // the line stands as a whole line, the turn has 8+ letters, an ambiguous record
    // blocks, and all accepted readings must agree on one translation. No fuzzy layer.
    private func alternateMatch(_ text: String) -> (String, String)? {
        guard !lineAlternates.isEmpty,
              Self.normalized(text).unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 5
        else { return nil }
        var hits: [String: String] = [:]
        for (line, readings) in lineAlternates {
            guard let range = Self.wholeLineRange(of: line, in: text) else { continue }
            let primary = Self.normalized(line)
            for reading in readings {
                let key = Self.normalized(reading)
                guard key != primary, key.count >= primary.count,
                      Self.editDistanceWithin(primary, key, limit: 2) != nil else { continue }
                let candidate = text.replacingCharacters(in: range, with: reading)
                if queryVariants(candidate).contains(where: { ambiguousExact.contains($0) }) { return nil }
                if let translation = exactMatch(candidate) { hits[translation] = candidate }
            }
        }
        guard hits.count == 1, let hit = hits.first else { return nil }
        return (hit.value, hit.key)
    }

    /// The only occurrence of `line` in `text`, bounded by line breaks, spaces or the ends.
    private static func wholeLineRange(of line: String, in text: String) -> Range<String.Index>? {
        guard !line.isEmpty else { return nil }
        var found: Range<String.Index>?
        var searchStart = text.startIndex
        while let range = text.range(of: line, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if (before == nil || before!.isWhitespace) && (after == nil || after!.isWhitespace) {
                guard found == nil else { return nil }
                found = range
            }
            searchStart = text.index(after: range.lowerBound)
        }
        return found
    }

    /// Layout already supplies blank lines. Single line breaks are merely possible
    /// boundaries, and breaks inside an open quotation always remain part of one unit.
    private static func dialogueUnits(_ text: String) -> [String] {
        // Split only complete turns from the start of a line. Embedded phrases
        // followed by narrative text are never promoted to independent turns.
        let pattern = "^([\\p{Han}\\p{Katakana}A-Za-z・]{0,12}[「『(（].*?[」』)）])[ \\t　]*(?=[\\p{Han}\\p{Katakana}A-Za-z・]{0,12}[「『(（])"
        var preparedLines: [String] = []
        for line in text.components(separatedBy: "\n") {
            var rest = line
            while let range = rest.range(of: pattern, options: .regularExpression) {
                preparedLines.append(String(rest[range]))
                rest = String(rest[range.upperBound...])
            }
            preparedLines.append(rest)
        }
        let prepared = preparedLines.joined(separator: "\n")
        var units: [String] = []
        var current: [String] = []
        var stack: [Character] = []
        for line in prepared.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            current.append(trimmed)
            for character in trimmed {
                if character == "「" { stack.append("」") }
                else if character == "『" { stack.append("』") }
                else if character == "（" { stack.append("）") }
                else if character == "(" { stack.append(")") }
                else if stack.last == character { stack.removeLast() }
            }
            // Keep incomplete unquoted sentences with the following wrapped line too.
            if stack.isEmpty, let last = trimmed.last, "。！？.!?」』)）".contains(last) {
                units.append(current.joined(separator: "\n"))
                current.removeAll()
            }
        }
        if !current.isEmpty { units.append(current.joined(separator: "\n")) }
        return units
    }

    private static func isClosedTurn(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.contains("「") && trimmed.last == "」")
            || (trimmed.contains("『") && trimmed.last == "』")
            || (trimmed.contains("（") && trimmed.last == "）")
            || (trimmed.contains("(") && trimmed.last == ")")
    }

    // Real screenshots 2026-11-09: long turns misread by two characters (貴方のことは →
    // 貴方の5点は; 空木 → 塾米 under ruby) stayed unmatched, because score >= 0.97 allows
    // a second error only from 67 characters. Extra rule, tried only after the original
    // one fails: both texts 34+ characters and of equal length (misread characters only -
    // an extra short line such as a name or menu word must not be swallowed), the best
    // record within 2 edits, and no record with a different translation within
    // `twoEditRivalLimit` edits.
    static let twoEditMinimumLength = 34
    static let twoEditRivalLimit = 4

    private func fuzzyMatch(_ text: String) -> String? {
        guard let rows, !Self.hasUnclosedOpening(text) else { return nil }
        var scores: [String: Double] = [:]
        // Per translation: the smallest distance and whether that record is long enough.
        var nearest: [String: (distance: Int, long: Bool)] = [:]
        for strictQuery in queryVariants(text) where strictQuery.count >= 28 {
            let query = Self.looseKey(strictQuery)
            let queryLength = strictQuery.count
            for (index, votes) in candidateRows(for: query) where votes >= 2 {
                let key = rows[index].key
                let maxLength = max(rows[index].strictLength, queryLength)
                guard Double(min(rows[index].strictLength, queryLength)) / Double(maxLength) >= 0.90 else { continue }
                // Score near misses as well, so a just-below-threshold rival still blocks
                // an ambiguous result. No unbounded substring/containment acceptance.
                let limit = max(1, Int(Double(maxLength) * 0.10))
                let searchLimit = query.count >= Self.twoEditMinimumLength ? max(limit, Self.twoEditRivalLimit) : limit
                let rawDistance = Self.editDistanceWithin(query, key, limit: searchLimit)
                let foldedDistance: Int? = {
                    guard (rawDistance ?? Int.max) > 1, query.contains("…"), key.contains("…") else { return nil }
                    let fq = Self.ellipsisSokuonKey(query), fk = Self.ellipsisSokuonKey(key)
                    guard fq != query || fk != key else { return nil }
                    return Self.editDistanceWithin(fq, fk, limit: searchLimit)
                }()
                let useFolded = foldedDistance != nil && (rawDistance == nil || foldedDistance! < rawDistance!)
                guard let distance = useFolded ? foldedDistance : rawDistance else { continue }
                let translation = rows[index].translation
                let long = query.count >= Self.twoEditMinimumLength
                    && (useFolded ? Self.ellipsisSokuonKey(key).count == Self.ellipsisSokuonKey(query).count
                        : rows[index].key.count == query.count)
                if let old = nearest[translation], old.distance <= distance {} else {
                    nearest[translation] = (distance, long)
                }
                guard distance <= limit else { continue }
                let score = 1.0 - Double(distance) / Double(maxLength)
                scores[translation] = max(scores[translation] ?? 0, score)
            }
        }
        let ranked = scores.sorted { $0.value > $1.value }
        if let best = ranked.first, best.value >= 0.97,
           best.value - (ranked.dropFirst().first?.value ?? 0) >= 0.02 {
            return best.key
        }
        let byDistance = nearest.sorted { $0.value.distance < $1.value.distance }
        guard let best = byDistance.first, best.value.long, best.value.distance <= 2,
              byDistance.dropFirst().allSatisfy({ $0.value.distance > Self.twoEditRivalLimit })
        else { return nil }
        return best.key
    }

    private func lookup(_ text: String, repairingQuotes: Bool = true) -> String? {
        if queryVariants(text).contains(where: { ambiguousExact.contains($0) }) { return nil }
        if let hit = exactMatch(text) { return hit }
        if let hit = longVowelMatch(text) { return hit }
        if let hit = ellipsisSokuonMatch(text) { return hit }
        if let hit = smallKanaMatch(text) { return hit }
        if let hit = leadingSymbolMatch(text) { return hit }
        if let hit = leadingDashMatch(text) { return hit }
        if let hit = dashDroppedMatch(text) { return hit }
        if let hit = droppedStraightQuoteMatch(text) { return hit }
        if let hit = quotedPhraseMatch(text) { return hit }
        if let hit = angleBracketMatch(text) { return hit }
        if let hit = tailMatch(text) { return hit }
        if let hit = lookAlikeMatch(text) { return hit }
        // A missing final quote is not permission to match an unrelated unquoted record.
        // Only restore one closing delimiter when the entire long body is an exact record.
        if !Self.balanced(text) {
            for query in queryVariants(text) where query.count >= 28 {
                if let first = query.first, let close = Self.quotePairs[first],
                   Self.balanced(query + String(close)), let hit = exact[query + String(close)] { return hit }
            }
            if let hit = edgeQuoteMatch(text) { return hit }
            if repairingQuotes {
                let repaired = Set(Self.quoteRepairs(text).compactMap { lookup($0, repairingQuotes: false) })
                if let hit = Self.single(repaired) { return hit }
            }
            return Self.hasUnclosedOpening(text) ? nil : fuzzyMatch(text)
        }
        let repaired = repairMatch(text)
        if repaired.blocked { return nil }
        return repaired.translation ?? fuzzyMatch(text) ?? oneEditMatch(text)
    }

    // MARK: - 2026-11-14 rules (Money Parasite / DistortedCode / 闇色の魔珠 feedback)

    private static func letterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    }

    private static let runFoldPattern = try! NSRegularExpression(pattern: "[…‥.。・·⋯]+|[—―─–-]+|\\s+")

    /// Translations that differ only in how long an ellipsis or dash run is
    /// (「……诶？」 / 「…………诶？」) are the same line for matching purposes.
    private static func foldedTranslation(_ translation: String) -> String {
        runFoldPattern.stringByReplacingMatches(in: translation, range: NSRange(translation.startIndex..., in: translation),
                                                withTemplate: "…")
    }

    /// The one translation all candidates agree on (run lengths aside), else nil.
    private static func single(_ translations: Set<String>) -> String? {
        guard let first = translations.min() else { return nil }
        return Set(translations.map(foldedTranslation)).count == 1 ? first : nil
    }

    // Trailing punctuation is where the thin outlined font of Money Parasite fails most:
    // the closing quote is lost (「相手の気持ちを、汲み取る…… for …？」), dots turn into
    // 「！」 (（そう、だったんだ……） read as …!!）), a final ――。 becomes ー. Records are
    // indexed by their loose key minus the trailing punctuation run; a query treated the
    // same way must have 4+ letters and every record sharing the stem must agree on one
    // translation, so 「え……」/「え？」/「え！」 stay unmatched.
    // The run is everything after the last letter or digit, plus a final ー/一 (a dash
    // remnant): it also covers a click-wait icon read as a symbol (本当にそんな事が？*).
    private static func stemKey(_ loose: String) -> String {
        var end = loose.endIndex
        while end > loose.startIndex {
            let character = loose[loose.index(before: end)]
            let wordLike = character.unicodeScalars.contains {
                CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
            }
            guard !wordLike || character == "ー" || character == "一" else { break }
            end = loose.index(before: end)
        }
        return String(loose[..<end])
    }

    private func tailMatch(_ text: String) -> String? {
        for query in queryVariants(text) {
            // Vision often reads a hollow period `。` after a dash (`すると───。`) as `o` (`すると一 o`).
            var adjusted = query
            if let last = adjusted.last, last == "o" || last == "°",
               adjusted.count >= 2,
               "―─—–ー一-".contains(adjusted[adjusted.index(adjusted.endIndex, offsetBy: -2)]) {
                adjusted.removeLast()
                adjusted.append("。")
            }
            let loose = Self.looseKey(adjusted)
            let stem = Self.stemKey(loose)
            let letters = Self.letterCount(stem)
            let tail = loose[stem.endIndex...]
            let shortDashNarration = letters == 3
                && !stem.contains(where: { "「」『』()（）".contains($0) })
                && tail.contains(where: { "―─—–ー一-".contains($0) })
                && !tail.contains(where: { "!?！？".contains($0) })
            guard letters >= 4 || shortDashNarration,
                  let translations = stemIndex[stem] else { continue }
            return Self.single(translations)
        }
        return nil
    }

    // The opening 「 of that font is read as I / 1 / T or dropped (「嫌ですが？」 → 1嫌ですが？」,
    // 「！」 → I！」), a closing 」 as 1 / I. Restore the missing delimiter and accept an
    // exact (strict/loose) record only. A bare prepend needs 4+ letters so the tail of a
    // wrapped turn (ね」) is not promoted to a record of its own.
    private static let quoteLookAlikes = Set("IlT1|[]iJ")
    private static let openers: [Character: Character] = ["」": "「", "』": "『", ")": "(", "）": "（"]

    private func edgeQuoteMatch(_ text: String) -> String? {
        let key = Self.normalized(text)
        let chars = Array(key)
        guard chars.count >= 2, !Self.balanced(key) else { return nil }
        var candidates: [String] = []
        if let open = Self.openers[chars[chars.count - 1]], !Self.hasUnclosedOpening(key) {
            if Self.letterCount(key) >= 4 { candidates.append(String(open) + key) }
            if Self.quoteLookAlikes.contains(chars[0]) { candidates.append(String(open) + String(chars.dropFirst())) }
        }
        if let close = Self.quotePairs[chars[0]], Self.quoteLookAlikes.contains(chars[chars.count - 1]) {
            candidates.append(String(chars.dropLast()) + String(close))
        }
        var translations = Set<String>()
        for candidate in candidates where Self.balanced(candidate) {
            if ambiguousExact.contains(candidate) { return nil }
            if let translation = exact[candidate] { translations.insert(translation); continue }
            let loose = Self.looseKey(candidate)
            if ambiguousLoose.contains(loose) { return nil }
            if let translation = looseExact[loose] { translations.insert(translation) }
        }
        if let hit = Self.single(translations) { return hit }
        // Vision sometimes drops the entire opening `「……───` on a low-contrast background,
        // leaving `body」` (6+ letters) with no plain `「body」` in the database.
        if let open = Self.openers[chars[chars.count - 1]], open == "「" || open == "『",
           !Self.hasUnclosedOpening(key), Self.letterCount(key) >= 6 {
            let plain = String(open) + key
            let loosePlain = Self.looseKey(plain)
            if !ambiguousExact.contains(plain), !ambiguousLoose.contains(loosePlain),
               exact[plain] == nil, looseExact[loosePlain] == nil,
               let candidates = leadingSymbolIndex[Self.looseKey(key)],
               let hit = Self.single(candidates) {
                return hit
            }
        }
        return nil
    }

    /// 『スリーカード」 / 「『かがみ』 read as 「「かがみ』: make the quote types pair up, once
    /// by trusting the openers and once by trusting the closers. The caller runs the
    /// normal lookup on each and requires them to agree.
    private static func quoteRepairs(_ text: String) -> [String] {
        let closers = Set(quotePairs.values)
        var forward = Array(text), stack: [Character] = [], changed = false
        for index in forward.indices {
            let c = forward[index]
            if let close = quotePairs[c] { stack.append(close) }
            else if closers.contains(c), let expected = stack.popLast(), expected != c {
                forward[index] = expected
                changed = true
            }
        }
        var results: [String] = []
        if changed, balanced(String(forward)) { results.append(String(forward)) }
        var backward = Array(text)
        stack = []
        changed = false
        for index in backward.indices.reversed() {
            let c = backward[index]
            if let open = openers[c] { stack.append(open) }
            else if quotePairs[c] != nil, let expected = stack.popLast(), expected != c {
                backward[index] = expected
                changed = true
            }
        }
        if changed, balanced(String(backward)), !results.contains(String(backward)) { results.append(String(backward)) }
        return results
    }

    // One line on screen can be two or three consecutive records (Money Parasite 1371/1372:
    // ……でも、彼も理解しているだろう。 + 私のあの態度を見れば。; 1727/1728 split inside a
    // quote: 「え…… + えっ、もうこんな時間なのっ！？」). After everything else fails, cut the
    // text into pieces that are each an exact (strict/loose) record and sit next to each
    // other in the database, in order. Every valid cut must give the same result.
    private func piece(_ key: String) -> (translation: String, ids: [Int64])? {
        if ambiguousExact.contains(key) { return nil }
        if let translation = exact[key], let ids = exactPositions[key] { return (translation, ids) }
        let loose = Self.looseKey(key)
        if ambiguousLoose.contains(loose) { return nil }
        if let translation = looseExact[loose], let ids = loosePositions[loose] { return (translation, ids) }
        return nil
    }

    private static func follows(_ first: [Int64], _ second: [Int64]) -> Bool {
        let next = Set(second)
        return first.contains { next.contains($0 + 1) }
    }

    private func splitMatch(_ text: String) -> String? {
        for query in queryVariants(text) {
            let chars = Array(query)
            guard chars.count >= 6, chars.count <= 240, Self.letterCount(query) >= 8 else { continue }
            var results = Set<String>()
            for cut in 2...(chars.count - 2) {
                guard let left = piece(String(chars[..<cut])) else { continue }
                let rest = Array(chars[cut...])
                if let right = piece(String(rest)), Self.follows(left.ids, right.ids) {
                    results.insert(left.translation + right.translation)
                    continue
                }
                guard rest.count >= 4 else { continue }
                for second in 2...(rest.count - 2) {
                    guard let middle = piece(String(rest[..<second])), Self.follows(left.ids, middle.ids),
                          let right = piece(String(rest[second...])), Self.follows(middle.ids, right.ids) else { continue }
                    results.insert(left.translation + middle.translation + right.translation)
                }
            }
            if results.count == 1 { return results.first }
            if results.count > 1 { return nil }
        }
        return nil
    }

    // Opt-in with the look-alike setting (default off): a line of 10+ characters with one
    // character misread, dropped or added (元気 → 完気, 十萌 → 十前, 親近感 → 親感) is too
    // short for the fuzzy layer. Accept the only record within one edit when no record
    // with another translation lies within two.
    static let oneEditMinimumLength = 10

    private func oneEditMatch(_ text: String) -> String? {
        guard lookAlikeEnabled, let rows, Self.balanced(text) else { return nil }
        for strictQuery in queryVariants(text) {
            let query = Self.looseKey(strictQuery)
            let count = query.count
            guard count >= Self.oneEditMinimumLength, Self.letterCount(query) >= 8 else { continue }
            var nearest: [String: (distance: Int, translation: String)] = [:]
            for length in (count - 2)...(count + 2) {
                for index in lengthBuckets[length] ?? [] {
                    guard let distance = Self.editDistanceWithin(query, rows[index].key, limit: 2) else { continue }
                    let folded = Self.foldedTranslation(rows[index].translation)
                    if let old = nearest[folded], old.distance <= distance { continue }
                    nearest[folded] = (distance, rows[index].translation)
                }
            }
            guard nearest.count == 1, let only = nearest.first?.value, only.distance <= 1 else { continue }
            return only.translation
        }
        return nil
    }

    private static let quotePairs: [Character: Character] = ["「": "」", "『": "』", "（": "）", "(": ")"]

    // Real screenshots 2026-11-06 (0036): Vision reads a word-final long vowel after
    // kanji as the kanji 一 (鷺澤ー！ → 鷺澤一！). Only retry the exact layer, and only
    // when every retried form agrees on one translation.
    private static let finalVowelPattern = try! NSRegularExpression(
        pattern: "(?<=[\\p{Han}\\p{Hiragana}\\p{Katakana}])一(?=[!?」』….、。]|$)")

    private func longVowelMatch(_ text: String) -> String? {
        let key = Self.normalized(text)
        let range = NSRange(key.startIndex..., in: key)
        guard Self.finalVowelPattern.firstMatch(in: key, range: range) != nil else { return nil }
        let variant = Self.finalVowelPattern.stringByReplacingMatches(in: key, range: range, withTemplate: "ー")
        guard variant != key else { return nil }
        return exactMatch(variant)
    }

    // Real screenshots 2026-11-06 (0022, 0028) & 2026-11-18 (色ドリ撫子 16167 / 17583):
    // an opening 「……─── is split off and misread (「……」」「．」」, …・・・」断る」,
    // ・…・・・・・」ーでも」) or lost. Records that start with a quote plus an
    // ellipsis/dash run are indexed by the remaining body, closing quote included.
    private static let leadingRunCharacters = Set(".・•⋯…‥―─—–-")
    private var leadingSymbolIndex: [String: Set<String>] = [:]
    /// Subset of `leadingSymbolIndex` whose leading run contains a dash (`「……───でも」`),
    /// so a query with a dash remnant (`・…・・・・・」ーでも」`) prefers it over `「……でも」`.
    private var leadingDashSymbolIndex: [String: Set<String>] = [:]

    private static func leadingSymbolBody(ofRecord key: String) -> (body: String, hasDash: Bool)? {
        let chars = Array(key)
        guard chars.count > 2, chars[0] == "「" || chars[0] == "『" else { return nil }
        var end = 1
        var hasDash = false
        while end < chars.count && leadingRunCharacters.contains(chars[end]) {
            if "―─—–-".contains(chars[end]) { hasDash = true }
            end += 1
        }
        guard end > 1 else { return nil }
        return (looseKey(String(chars[end...])), hasDash)
    }

    private func leadingSymbolMatch(_ text: String) -> String? {
        for candidate in queryVariants(text) where candidate.last == "」" || candidate.last == "』" {
            if let hit = matchLeadingSymbol(candidate, treatKanjiOneAsDash: false) { return hit }
            if let hit = matchLeadingSymbol(candidate, treatKanjiOneAsDash: true) { return hit }
        }
        return nil
    }

    private func matchLeadingSymbol(_ key: String, treatKanjiOneAsDash: Bool) -> String? {
        guard let firstLetter = key.firstIndex(where: {
            $0 != "ー" && !(treatKanjiOneAsDash && $0 == "一")
                && $0.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }), firstLetter > key.startIndex else { return nil }
        let prefix = key[..<firstLetter]
        let runCount = prefix.filter { Self.leadingRunCharacters.contains($0) }.count
        // Only treat kanji `一` (misread from `—`/`─`) as a dash when preceded by 2+ run symbols.
        if treatKanjiOneAsDash && (!prefix.contains("一") || runCount < 2) { return nil }
        // Vision sometimes reads the opening 「 before ……─── as a vertical stroke (！/!/I/1).
        let prefixRest: Substring = if runCount >= 3, let first = prefix.first,
            Self.quoteLookAlikes.contains(first) || "！!".contains(first) {
            prefix.dropFirst()
        } else {
            prefix
        }
        guard runCount >= 1,
              prefixRest.allSatisfy({
                  Self.leadingRunCharacters.contains($0)
                      || "「」『』。、".contains($0)
                      || (runCount >= 2 && ($0 == "ー" || (treatKanjiOneAsDash && $0 == "一")))
              }) else { return nil }
        let body = String(key[firstLetter...])
        let strongRun = runCount >= 3 || (treatKanjiOneAsDash && runCount >= 2)
        let hasDash = prefix.contains(where: { "―─—–-ー".contains($0) || (treatKanjiOneAsDash && $0 == "一") })
        guard let close = body.last, close == "」" || close == "』",
              Self.letterCount(body) >= (strongRun ? 2 : 6),
              Self.balanced((close == "」" ? "「" : "『") + body) else { return nil }
        let looseBody = Self.looseKey(body)
        let translation: String
        if hasDash, let dashed = leadingDashSymbolIndex[looseBody], let hit = Self.single(dashed) {
            translation = hit
        } else if let all = leadingSymbolIndex[looseBody], let hit = Self.single(all) {
            translation = hit
        } else {
            return nil
        }
        // Only a weak prefix (1-2 stray dots) competes with the plain no-symbol record;
        // an explicit 3+ dot/dash run (`……───`) cannot be the plain line (`「断る」`).
        if !strongRun {
            let open: Character = close == "」" ? "「" : "『"
            if let plain = exact[String(open) + body], plain != translation { return nil }
            if ambiguousExact.contains(String(open) + body) { return nil }
        }
        return translation
    }

    // Real play 2026-11-18 (色ドリ撫子, records 49545 / 52782 / 53189): a narration line
    // starting with ─── has the leading dash run dropped or read as a single `-`
    // (───彼だからだ。 → -彼だからだ。, ───あれから一年。 → あれから一年。, ───『空舟櫂』。 → 『空舟櫂』。).
    // Too short for dashDroppedMatch (8+ letters) and unquoted for leadingSymbolMatch.
    // Index records starting with a dash run by their loose body; accept only balanced
    // bodies of 4+ letters (or 3+ inside 『…』) when every competing record agrees.
    private static let leadingDashCharacters = Set("―─—–-")
    private var leadingDashIndex: [String: Set<String>] = [:]

    private static func leadingDashBody(ofRecord key: String) -> String? {
        var index = key.startIndex
        while index < key.endIndex && "―─—–".contains(key[index]) {
            index = key.index(after: index)
        }
        guard index > key.startIndex, index < key.endIndex else { return nil }
        return looseKey(String(key[index...]))
    }

    private func leadingDashMatch(_ text: String) -> String? {
        let key = Self.normalized(text)
        if let hit = matchLeadingDash(key, allowKanjiOneOrLongVowel: false) { return hit }
        return matchLeadingDash(key, allowKanjiOneOrLongVowel: true)
    }

    private func matchLeadingDash(_ key: String, allowKanjiOneOrLongVowel: Bool) -> String? {
        var index = key.startIndex
        while index < key.endIndex
            && (Self.leadingDashCharacters.contains(key[index])
                || (allowKanjiOneOrLongVowel && "一ー".contains(key[index]))) {
            index = key.index(after: index)
        }
        guard !allowKanjiOneOrLongVowel || index > key.startIndex, index < key.endIndex else { return nil }
        let body = String(key[index...])
        if allowKanjiOneOrLongVowel {
            // Only strip a leading kanji `一` / `ー` when it precedes a digit/date or ASCII/quote,
            // so real words like `一日中` are never stripped into `日中`.
            guard let first = body.first, first.isNumber || "『「(".contains(first) else { return nil }
        }
        guard Self.balanced(body) else { return nil }
        let letters = Self.letterCount(body)
        let alnum = body.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }.count
        let titleQuoted = body.first == "『" && (body.last == "』" || body.hasSuffix("』。"))
        guard letters >= 4 || (letters >= 2 && alnum >= 4) || (titleQuoted && letters >= 3) else { return nil }
        let looseBody = Self.looseKey(body)
        guard var translations = leadingDashIndex[looseBody] else { return nil }
        if ambiguousExact.contains(body) || ambiguousLoose.contains(looseBody) { return nil }
        if let plain = exact[body] { translations.insert(plain) }
        if let plain = looseExact[looseBody] { translations.insert(plain) }
        return Self.single(translations)
    }

    // Real play 2026-11-09 (色ドリ撫子, record 52154): Vision dropped a line-final ───
    // entirely (和綴じ本に───アウラはない。 read as 和綴じ本に / アウラはない。). The turn is
    // too short for the fuzzy layer and one length off for the repair layer. Records
    // containing a dash run are indexed by their dash-free text; a query (dashes also
    // removed) must have 8+ letters and every competing record - dashed or plain -
    // must agree on one translation.
    private static let dashRunPattern = try! NSRegularExpression(pattern: "[―─—–]+|[ー一-]{2,}")
    private var dashlessIndex: [String: Set<String>] = [:]
    /// 2026-11-15: the same index on loose keys. 「あの女性と僕は……───他人みたいなものだ」 was read
    /// with seven dots AND without the dash run; the strict index above only forgives the
    /// lost dashes, the loose key only the dot count. Same guards: 8+ letters, one translation.
    private var looseDashlessIndex: [String: Set<String>] = [:]

    private static func dashlessKey(_ key: String) -> String {
        dashRunPattern.stringByReplacingMatches(in: key, range: NSRange(key.startIndex..., in: key), withTemplate: "")
    }

    private func dashDroppedMatch(_ text: String) -> String? {
        for query in queryVariants(text) {
            let key = Self.dashlessKey(query)
            guard key.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 8,
                  var translations = dashlessIndex[key] else { continue }
            if ambiguousExact.contains(key) { return nil }
            if let plain = exact[key] { translations.insert(plain) }
            return translations.count == 1 ? translations.first : nil
        }
        for query in queryVariants(text) {
            let key = Self.dashlessKey(Self.looseKey(query))
            let letters = key.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count
            // 2026-11-20 (色ドリ撫子 55706): a short closed quote ending with ……─── read
            // without the dash (`「この国.......」`). Allow 3+ letters only when balanced,
            // ending in `…」`/`…』`, and no competing plain record exists.
            let shortQuotedEllipsis = letters >= 3 && Self.balanced(key)
                && (key.hasSuffix("…」") || key.hasSuffix("…』"))
            guard (letters >= 8 || shortQuotedEllipsis),
                  var translations = looseDashlessIndex[key] else { continue }
            if ambiguousExact.contains(key) || ambiguousLoose.contains(key) { return nil }
            if let plain = exact[key] { translations.insert(plain) }
            if let plain = looseExact[key] { translations.insert(plain) }
            return Self.single(translations)
        }
        return nil
    }

    // 2026-11-20 (色ドリ撫子 55138 / 56213 / 56355): Vision frequently reads `……っ` before
    // punctuation as `……•` (absorbed into `…`) or `……つ`. Index records with `…[っつ]` folded
    // to `…` before punctuation; require balanced quotes, 6+ letters, and zero competing
    // plain records with a different translation.
    private static let ellipsisSokuonPattern = try! NSRegularExpression(pattern: "…[っつ](?=[、。」』）)！？!?]|$)")
    private var ellipsisSokuonIndex: [String: Set<String>] = [:]

    private static func ellipsisSokuonKey(_ loose: String) -> String {
        guard loose.contains("…") else { return loose }
        return ellipsisSokuonPattern.stringByReplacingMatches(
            in: loose, range: NSRange(loose.startIndex..., in: loose), withTemplate: "…")
    }

    private func ellipsisSokuonMatch(_ text: String) -> String? {
        guard Self.balanced(text) else { return nil }
        for query in queryVariants(text) {
            let loose = Self.looseKey(query)
            guard loose.contains("…"), Self.letterCount(loose) >= 6 else { continue }
            let folded = Self.ellipsisSokuonKey(loose)
            guard var translations = ellipsisSokuonIndex[folded] else { continue }
            if ambiguousExact.contains(folded) || ambiguousLoose.contains(folded) { return nil }
            if let plain = exact[folded] { translations.insert(plain) }
            if let plain = looseExact[folded] { translations.insert(plain) }
            if let hit = Self.single(translations) { return hit }
        }
        return nil
    }

    // 2026-11-14 / 2026-11-20 (Money Parasite #53/#54): Vision drops one of a pair of
    // curly/straight quotes (`“ハイ＆ロウ”` -> `ハイ&ロウ"`), leaving an odd number of `"`.
    // Index records containing `"` by their quote-free loose key; accept long lines (10+
    // letters) with an odd `"` count only when every candidate agrees on one translation.
    private var straightQuoteLessIndex: [String: Set<String>] = [:]

    // 2026-11-20 (sins of KALEIDO): Vision reads small kana as full-size (はぁ→はあ, なぁ→なあ),
    // `〝...〟` with single `―` as `...ー、` or `"..ーミ`, and `〈...〉`/`《...》` as `<...)` / `く...>`.
    private static let smallKanaMap: [Character: Character] = [
        "ぁ": "あ", "ぃ": "い", "ぅ": "う", "ぇ": "え", "ぉ": "お",
        "ゃ": "や", "ゅ": "ゆ", "ょ": "よ", "っ": "つ",
    ]
    private var smallKanaIndex: [String: Set<String>] = [:]
    private var quotedBodyIndex: [String: Set<String>] = [:]
    private var angleBracketIndex: [String: Set<String>] = [:]

    private static func smallKanaFolded(_ key: String) -> String {
        guard key.contains(where: { smallKanaMap[$0] != nil }) else { return key }
        return String(key.map { smallKanaMap[$0] ?? $0 })
    }

    private static func dashToBarKey(_ key: String) -> String {
        guard key.rangeOfCharacter(from: dashCharacters) != nil else { return key }
        return String(key.map { "―─—–ー-".contains($0) ? "―" : $0 })
    }

    private static func angleBracketKey(_ loose: String) -> String {
        String(loose.map {
            switch $0 {
            case "〈", "《": "<"
            case "〉", "》": ">"
            default: $0
            }
        })
    }

    private func smallKanaMatch(_ text: String) -> String? {
        guard Self.balanced(text) else { return nil }
        for query in queryVariants(text) where Self.letterCount(query) >= 5 {
            let folded = Self.smallKanaFolded(Self.ellipsisSokuonKey(Self.looseKey(query)))
            guard var translations = smallKanaIndex[folded] else { continue }
            if ambiguousExact.contains(folded) || ambiguousLoose.contains(folded) { return nil }
            if let sokuon = ellipsisSokuonIndex[folded] { translations.formUnion(sokuon) }
            if let plain = exact[folded] { translations.insert(plain) }
            if let plain = looseExact[folded] { translations.insert(plain) }
            if let hit = Self.single(translations) { return hit }
        }
        return nil
    }

    private func quotedPhraseMatch(_ text: String) -> String? {
        guard Self.balanced(text), !quotedBodyIndex.isEmpty else { return nil }
        for query in queryVariants(text) where Self.letterCount(query) >= 10 {
            let loose = Self.looseKey(query)
            var forms = [loose]
            // 〝X―〟 read as Xー、 (opening quote dropped, closing quote read as `、`).
            if loose.contains("ー、") || loose.contains("―、") {
                forms.append(loose.replacingOccurrences(of: "([ー―])、", with: "$1", options: .regularExpression))
            }
            // `"X―ミ...` when `"` is odd and `〟` became `ミ` right after `ー`/`―`.
            if loose.filter({ $0 == "\"" }).count % 2 == 1 {
                forms.append(loose.replacingOccurrences(of: "(?<=[ー―])ミ(?=[…、。」』)])", with: "", options: .regularExpression))
            }
            for form in forms {
                let key = Self.smallKanaFolded(Self.dashToBarKey(form.replacingOccurrences(of: "\"", with: "")))
                guard var translations = quotedBodyIndex[key] else { continue }
                if ambiguousExact.contains(key) || ambiguousLoose.contains(key) { return nil }
                if let plain = exact[key] { translations.insert(plain) }
                if let plain = looseExact[key] { translations.insert(plain) }
                if let hit = Self.single(translations) { return hit }
            }
        }
        return nil
    }

    private func angleBracketMatch(_ text: String) -> String? {
        guard !angleBracketIndex.isEmpty,
              text.contains(where: { "〈〉《》<>＜＞く）)".contains($0) }) else { return nil }
        for query in queryVariants(text) {
            let base = Self.angleBracketKey(Self.looseKey(query))
            let repaired = Self.repairedAngleBrackets(base)
            var candidates = [repaired]
            if !Self.balanced(repaired) {
                candidates.append(contentsOf: Self.quoteRepairs(repaired))
            }
            var translations = Set<String>()
            for candidate in candidates where Self.balanced(candidate) {
                if ambiguousExact.contains(candidate) || ambiguousLoose.contains(candidate) { return nil }
                if let hit = angleBracketIndex[candidate] { translations.formUnion(hit) }
                if let plain = exact[candidate] { translations.insert(plain) }
                if let plain = looseExact[candidate] { translations.insert(plain) }
            }
            if let hit = Self.single(translations) { return hit }
        }
        return nil
    }

    private static func repairedAngleBrackets(_ input: String) -> String {
        var chars = Array(input)
        // Step 1: an unmatched `)` (no open `(`) closing an open `<` becomes `>`.
        var parenDepth = 0
        var hasOpenAngle = false
        for i in chars.indices {
            switch chars[i] {
            case "(": parenDepth += 1
            case ")":
                if parenDepth > 0 { parenDepth -= 1 }
                else if hasOpenAngle { chars[i] = ">"; hasOpenAngle = false }
            case "<": hasOpenAngle = true
            case ">": hasOpenAngle = false
            default: break
            }
        }
        // Step 2: `く` at a delimiter boundary (`start`, `『`, `「`, `、`, `>`) followed by `>` or
        // unmatched `)` (before any `<`, `「`, `『`) is a misread `<` (`く美術館の人になりたい>`).
        parenDepth = 0
        for i in chars.indices {
            if chars[i] == "(" { parenDepth += 1; continue }
            if chars[i] == ")" && parenDepth > 0 { parenDepth -= 1; continue }
            guard chars[i] == "く" else { continue }
            let atBoundary = i == 0 || "『「、>".contains(chars[i - 1])
            guard atBoundary else { continue }
            var depth = parenDepth
            var foundCloser: Int?
            for j in (i + 1)..<chars.count {
                let c = chars[j]
                if c == "(" { depth += 1 }
                else if c == ")" {
                    if depth > 0 { depth -= 1 }
                    else { foundCloser = j; break }
                } else if c == ">" {
                    foundCloser = j; break
                } else if "<「『".contains(c) {
                    break
                }
            }
            if let closer = foundCloser {
                chars[i] = "<"
                if chars[closer] == ")" { chars[closer] = ">" }
            }
        }
        return String(chars)
    }

    private func droppedStraightQuoteMatch(_ text: String) -> String? {
        guard Self.balanced(text) else { return nil }
        for query in queryVariants(text) {
            guard query.filter({ $0 == "\"" }).count % 2 == 1,
                  Self.letterCount(query) >= 10 else { continue }
            let stripped = Self.looseKey(query).replacingOccurrences(of: "\"", with: "")
            guard var translations = straightQuoteLessIndex[stripped] else { continue }
            if ambiguousExact.contains(stripped) || ambiguousLoose.contains(stripped) { return nil }
            if let plain = exact[stripped] { translations.insert(plain) }
            if let plain = looseExact[stripped] { translations.insert(plain) }
            if let hit = Self.single(translations) { return hit }
        }
        return nil
    }

    // 2026-11-09, opt-in (Settings, default off): OCR reads one character of a line as a
    // look-alike (仁科 → 化科, っつーか → つつーか, 鳥 → 島). Short lines get no fuzzy
    // matching, so swap one such character back and accept an exact (strict/loose) record
    // only when every accepted swap agrees on one translation and none is ambiguous.
    // Another record can sit exactly one look-alike away from the misread one and the
    // swap may land on it - a small chance of the wrong line, hence off by default.
    private static let lookAlikeGroups = [
        "仁化", "鳥島", "末未", "土士", "千干", "人入", "己已巳", "日曰", "屑層", "澄登",
        "っつ", "ゃや", "ゅゆ", "ょよ", "ぁあ", "ぃい", "ぅう", "ぇえ", "ぉお",
        "ッツ", "ャヤ", "ュユ", "ョヨ", "ァア", "ィイ", "ゥウヴ", "ェエ", "ォオ", "ヶケ",
        "ー一", "カ力", "ロ口", "エ工", "ニ二", "ハ八", "タ夕", "ト卜", "ヘへ", "ベべ", "ペぺ", "リり",
        "ばぱ", "びぴ", "ぶぷ", "べぺ", "ぼぽ", "バパ", "ビピ", "ブプ", "ベペ", "ボポ",
        "十+＋",
    ]
    private static let lookAlikes: [Character: [Character]] = {
        var map: [Character: Set<Character>] = [:]
        for group in lookAlikeGroups {
            for c in group { map[c, default: []].formUnion(group.filter { $0 != c }) }
        }
        return map.mapValues { Array($0).sorted() }
    }()

    private func lookAlikeMatch(_ text: String) -> String? {
        guard lookAlikeEnabled,
              Self.normalized(text).unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2
        else { return nil }
        let characters = Array(text)
        var translations = Set<String>()
        for (index, character) in characters.enumerated() {
            guard let alternatives = Self.lookAlikes[character] else { continue }
            for alternative in alternatives {
                var swapped = characters
                swapped[index] = alternative
                // Whole text only: query variants that strip a name-like first line would let
                // a swap inside a known first line (話に入る → 話に人る) turn it into a "name".
                let key = Self.normalized(String(swapped))
                // Relaxed punctuation only for a closed turn, as in exactMatch.
                let loose = Self.balanced(key) ? Self.looseKey(key) : nil
                if ambiguousExact.contains(key) || loose.map(ambiguousLoose.contains) == true { return nil }
                if let translation = exact[key] ?? loose.flatMap({ looseExact[$0] }), !translation.isEmpty {
                    translations.insert(translation)
                } else if let loose {
                    let letters = Self.letterCount(loose)
                    if letters >= 8 {
                        let dashless = Self.dashlessKey(loose)
                        if var candidates = looseDashlessIndex[dashless] {
                            if ambiguousExact.contains(dashless) || ambiguousLoose.contains(dashless) { return nil }
                            if let plain = exact[dashless] { candidates.insert(plain) }
                            if let plain = looseExact[dashless] { candidates.insert(plain) }
                            guard let hit = Self.single(candidates) else { return nil }
                            translations.insert(hit)
                        }
                    }
                    if letters >= 10, key.filter({ $0 == "\"" }).count % 2 == 1 {
                        let stripped = loose.replacingOccurrences(of: "\"", with: "")
                        if var candidates = straightQuoteLessIndex[stripped] {
                            if ambiguousExact.contains(stripped) || ambiguousLoose.contains(stripped) { return nil }
                            if let plain = exact[stripped] { candidates.insert(plain) }
                            if let plain = looseExact[stripped] { candidates.insert(plain) }
                            guard let hit = Self.single(candidates) else { return nil }
                            translations.insert(hit)
                        }
                    }
                }
                if translations.count > 1 { return nil }
            }
        }
        return translations.first
    }

    private static func hasUnclosedOpening(_ text: String) -> Bool {
        var stack: [Character] = []
        for c in text {
            if let close = quotePairs[c] { stack.append(close) }
            else if stack.last == c { stack.removeLast() }
        }
        return !stack.isEmpty
    }

    private static func balanced(_ text: String) -> Bool {
        var stack: [Character] = []
        for c in text {
            if let close = quotePairs[c] { stack.append(close) }
            else if quotePairs.values.contains(c) {
                guard stack.last == c else { return false }
                stack.removeLast()
            }
        }
        return stack.isEmpty
    }

    private static func katakana(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && c.unicodeScalars.first.map { (0x30A1...0x30FA).contains($0.value) } == true
    }

    // Keep quote types and all body punctuation. Only leading ellipsis and internal
    // katakana vowel marks share an index; candidates still face collision checks.
    private static let repairMarks = CharacterSet(charactersIn: "ー一―—")
    private static let internalVowelPattern = try! NSRegularExpression(pattern: "(?<=[ァ-ヺ])[ー一―—](?=[ァ-ヺ])")

    private static func needsRepairIndex(_ input: String) -> Bool {
        var start = input.startIndex
        if start < input.endIndex, quotePairs[input[start]] != nil { start = input.index(after: start) }
        if start < input.endIndex && ".・•⋯…‥".contains(input[start]) { return true }
        guard input.rangeOfCharacter(from: repairMarks) != nil else { return false }
        return internalVowelPattern.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil
    }

    private static func repairKey(_ input: String) -> String? {
        guard balanced(input) else { return nil }
        var chars = Array(input)
        var start = 0
        if let first = chars.first, quotePairs[first] != nil { start = 1 }
        var end = start
        while end < chars.count && ".・•⋯…‥".contains(chars[end]) { end += 1 }
        chars.removeSubrange(start..<end)
        let letters = chars.filter { $0.unicodeScalars.contains { CharacterSet.letters.contains($0) } }.count
        guard letters >= 3 else { return nil }
        if chars.count >= 3 {
            for i in 1..<(chars.count - 1) where "一―—ー".contains(chars[i]) {
                if katakana(chars[i - 1]) && katakana(chars[i + 1]) { chars[i] = "ー" }
            }
        }
        return String(chars)
    }

    private static func repairDistance(_ input: String, _ source: String) -> Int? {
        func body(_ s: String) -> [Character] {
            var chars = Array(s)
            let start = chars.first.map { quotePairs[$0] != nil ? 1 : 0 } ?? 0
            var end = start
            while end < chars.count && ".・•⋯…‥".contains(chars[end]) { end += 1 }
            chars.removeSubrange(start..<end)
            return chars
        }
        let a = body(input), b = body(source)
        guard a.count == b.count else { return nil }
        let distance = zip(a, b).filter { $0 != $1 }.count
        return distance <= 2 ? distance : nil
    }

    private func repairMatch(_ text: String) -> (translation: String?, blocked: Bool) {
        guard let rows else { return (nil, false) }
        var candidates: [Int64: String] = [:]
        for query in queryVariants(text) {
            guard let key = Self.repairKey(query) else { continue }
            // Unchanged counterparts need no second full index. Reuse the exact map
            // so a bare sentence still competes with its ellipsis-prefixed variant.
            if key != query, Self.repairDistance(query, key) != nil {
                if ambiguousExact.contains(key) { return (nil, true) }
                if let translation = exact[key] {
                    for id in exactPositions[key] ?? [] { candidates[id] = translation }
                }
            }
            for index in repairIndex[key] ?? [] {
                let row = rows[index]
                guard row.strictKey != query, Self.repairDistance(query, row.strictKey) != nil else { continue }
                candidates[row.id] = row.translation
            }
        }
        guard !candidates.isEmpty else { return (nil, false) }
        let translations = Set(candidates.values)
        if translations.count == 1 { return (translations.first, false) }
        // Context never resolves arbitrary fuzzy ties. It only narrows these exact-body,
        // known-symbol candidates after two consecutive exact anchors, once per frame.
        if contextEnabled, reliableRun >= 2, !contextUsed, let anchor = lastExactID {
            let nearby = candidates.filter { $0.key > anchor && $0.key <= anchor + contextWindow }
            let values = Set(nearby.values)
            if values.count == 1 {
                contextUsed = true
                reliableRun = 0 // A recovery cannot seed a chain of speculative matches.
                return (values.first, false)
            }
        }
        return (nil, true)
    }

    private func renderMatch(_ text: String, _ translation: String) -> String {
        let normalized = Self.normalized(text)
        let substantial = normalized.filter { $0.unicodeScalars.contains { CharacterSet.letters.contains($0) } }.count >= 8
        if exact[normalized] == translation {
            guard let positions = exactPositions[normalized], positions.count == 1 else {
                resetContext()
                return translation
            }
            let id = positions[0]
            guard substantial else {
                if let anchor = lastExactID, id < anchor || id > anchor + contextWindow { resetContext() }
                return translation
            }
            if id != lastExactID {
                reliableRun = lastExactID.map { id > $0 && id <= $0 + contextWindow ? reliableRun + 1 : 1 } ?? 1
                lastExactID = id
            }
            consecutiveMisses = 0
            return translation
        }
        // The whole text, first line included, is one record minus its dashes
        // (もちろんそれは───『彼』のせいだ。 wrapped where the dash was lost): no prefix.
        if dashlessIndex[Self.dashlessKey(normalized)] == [translation] { return translation }
        if looseDashlessIndex[Self.dashlessKey(Self.looseKey(normalized))] == [translation] { return translation }
        // A separated prefix may be a speaker or a short narrative. Preserve it
        // whenever matching succeeds only after removing it.
        let layout = text.precomposedStringWithCompatibilityMapping
        if let opening = layout.firstIndex(where: { Self.quotePairs[$0] != nil }) {
            let raw = String(layout[..<opening])
            let prefix = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let dialogue = String(layout[opening...])
            if !prefix.isEmpty, raw.last?.isWhitespace == true,
               !prefix.contains(where: { "「」『』()（）。、！？!?".contains($0) }) {
                // The preserved prefix is not an anchor, but an independently exact
                // dialogue still can be. This also works when every frame has a name.
                return "［原文前缀］\n" + prefix + "\n\n" + renderMatch(dialogue, translation)
            }
        }
        return translation
    }

    private func candidateRows(for query: String) -> [(Int, Int)] {
        let chars = Array(query)
        guard chars.count >= 5 else { return [] }
        var votes: [Int: Int] = [:]
        var visited = Set<String>()
        for offset in 0...(chars.count - 5) {
            let gram = String(chars[offset..<(offset + 5)])
            guard visited.insert(gram).inserted else { continue }
            guard let rowIndices = anchors[gram], rowIndices.count <= 500 else { continue }
            for row in rowIndices { votes[row, default: 0] += 1 }
        }
        return votes.sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    private func loadDatabase() throws {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw TranslationError.translationFailed(L10n.lunaFileMissing)
        }
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw TranslationError.translationFailed(L10n.lunaOpenFailed(message))
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT source, machineTrans, rowid FROM artificialtrans ORDER BY rowid", -1, &statement, nil) == SQLITE_OK,
              let query = statement else {
            throw TranslationError.translationFailed(L10n.lunaNotStandard)
        }
        defer { sqlite3_finalize(query) }

        var result: [Entry] = []
        var seen: [String: Set<String>] = [:]
        while sqlite3_step(query) == SQLITE_ROW {
            autoreleasepool {
            guard let sourcePtr = sqlite3_column_text(query, 0),
                  let translationPtr = sqlite3_column_text(query, 1) else { return }
            let key = Self.normalized(String(cString: sourcePtr))
            guard !key.isEmpty,
                  let translation = Self.extractTranslation(String(cString: translationPtr)) else { return }
            let id = sqlite3_column_int64(query, 2)
            exactPositions[key, default: []].append(id)
            let loose = Self.looseKey(key)
            loosePositions[loose, default: []].append(id)
            guard !(seen[key]?.contains(translation) ?? false) else { return }
            seen[key, default: []].insert(translation)
            stemIndex[Self.stemKey(loose), default: []].insert(translation)
            lengthBuckets[loose.count, default: []].append(result.count)
            if Self.needsRepairIndex(key), let repair = Self.repairKey(key) { repairIndex[repair, default: []].append(result.count) }
            if let sym = Self.leadingSymbolBody(ofRecord: key) {
                leadingSymbolIndex[sym.body, default: []].insert(translation)
                if sym.hasDash { leadingDashSymbolIndex[sym.body, default: []].insert(translation) }
            }
            if let body = Self.leadingDashBody(ofRecord: key) { leadingDashIndex[body, default: []].insert(translation) }
            let dashless = Self.dashlessKey(key)
            if dashless != key { dashlessIndex[dashless, default: []].insert(translation) }
            let looseDashless = Self.dashlessKey(loose)
            if looseDashless != loose { looseDashlessIndex[looseDashless, default: []].insert(translation) }
            let sokuonFolded = Self.ellipsisSokuonKey(loose)
            if sokuonFolded != loose { ellipsisSokuonIndex[sokuonFolded, default: []].insert(translation) }
            let smallFolded = Self.smallKanaFolded(sokuonFolded)
            if smallFolded != sokuonFolded { smallKanaIndex[smallFolded, default: []].insert(translation) }
            if loose.contains("\"") {
                let stripped = loose.replacingOccurrences(of: "\"", with: "")
                if !stripped.isEmpty {
                    straightQuoteLessIndex[stripped, default: []].insert(translation)
                    let quotedBody = Self.smallKanaFolded(Self.dashToBarKey(stripped))
                    if !quotedBody.isEmpty { quotedBodyIndex[quotedBody, default: []].insert(translation) }
                }
            }
            if loose.contains(where: { "〈〉《》<>".contains($0) }) {
                angleBracketIndex[Self.angleBracketKey(loose), default: []].insert(translation)
            }
            result.append(Entry(key: loose, strictKey: key, id: id, strictLength: key.count, translation: translation))
            if let prior = looseExact[loose], prior != translation {
                // 「……え？」 and 「…………え？」 translated with the same run lengths: one line.
                if Self.foldedTranslation(prior) != Self.foldedTranslation(translation) {
                    ambiguousLoose.insert(loose)
                    looseExact.removeValue(forKey: loose)
                }
            } else if !ambiguousLoose.contains(loose) { looseExact[loose] = translation }
            if seen[key]!.count > 1 {
                ambiguousExact.insert(key)
                exact.removeValue(forKey: key)
            } else {
                exact[key] = translation
            }
        }
            }
        guard !result.isEmpty else {
            throw TranslationError.translationFailed(L10n.lunaNoRows)
        }
        // Sample a handful of anchors per row, not every 5-gram; avoids large RAM usage.
        for (index, row) in result.enumerated() {
            let chars = Array(row.key)
            guard chars.count >= 18 else { continue }
            let span = chars.count - 5
            let step = max(4, span / 6)
            var position = 0
            var used = Set<String>()
            while position <= span {
                let gram = String(chars[position..<(position + 5)])
                if used.insert(gram).inserted { anchors[gram, default: []].append(index) }
                position += step
            }
            let tail = String(chars[span..<(span + 5)])
            if used.insert(tail).inserted { anchors[tail, default: []].append(index) }
        }
        rows = result
    }

    /// 2026-11-14: curly and prime quotes all become the straight one (the database writes
    /// “ハイ＆ロウ”, Vision reads "ハイ＆ロウ"), the wave dash 〜 becomes the tilde that ～
    /// already maps to, and the Latin middle dot joins the ellipsis family.
    private static let foldedScalars: [UInt32: String] = [
        0x201C: "\"", 0x201D: "\"", 0x201E: "\"", 0x201F: "\"", 0x2033: "\"", 0x301D: "\"", 0x301E: "\"", 0x301F: "\"",
        0x301C: "~", 0x00B7: "・",
        // 2026-11-15: the other round dots Vision may return for 「……」 (‧ ∙ ⋅); ･ is already
        // folded by the compatibility mapping.
        0x2027: "・", 0x2219: "・", 0x22C5: "・",
    ]

    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0.value != 0x200B }
            .map { foldedScalars[$0.value] ?? String($0) }.joined()
    }

    private static let ellipsisCharacters = CharacterSet(charactersIn: ".・•⋯")
    private static let dashCharacters = CharacterSet(charactersIn: "―─—–ー一-")
    private static let ellipsisPattern = try! NSRegularExpression(pattern: "[.・•⋯]{2,}|⋯")
    private static let dashPattern = try! NSRegularExpression(pattern: "[―─—–ー一-]{2,}")
    private static let postEllipsisDashPattern = try! NSRegularExpression(pattern: "(?<=…)[―─—–ー-](?=[っつ」』）)。！？!?]|$)")

    private static func looseKey(_ key: String) -> String {
        var result = key
        // Reuse compiled patterns; Foundation's character-set scan skips absent families.
        if result.rangeOfCharacter(from: ellipsisCharacters) != nil {
            result = ellipsisPattern.stringByReplacingMatches(in: result,
                range: NSRange(result.startIndex..., in: result), withTemplate: "…")
        }
        if result.rangeOfCharacter(from: dashCharacters) != nil {
            result = dashPattern.stringByReplacingMatches(in: result,
                range: NSRange(result.startIndex..., in: result), withTemplate: "―")
            if result.contains("…") {
                result = postEllipsisDashPattern.stringByReplacingMatches(in: result,
                    range: NSRange(result.startIndex..., in: result), withTemplate: "―")
            }
        }
        return result
    }

    private func queryVariants(_ original: String) -> [String] {
        let normalizedInput = Self.normalized(original)
        var candidates: [String] = []
        func add(_ string: String) {
            guard !string.isEmpty, !candidates.contains(string) else { return }
            candidates.append(string)
        }
        func stripQuotes(_ string: String) -> String {
            string.trimmingCharacters(in: CharacterSet(charactersIn: "()（）「」『』\"'。！？,，、 "))
        }
        add(normalizedInput)
        if Self.balanced(normalizedInput) { add(stripQuotes(normalizedInput)) }

        // Preserve layout until deciding whether the speaker label is separated.
        let layout = original.precomposedStringWithCompatibilityMapping
        for opening in ["「", "『", "("] {
            if let range = layout.range(of: opening) {
                let rawPrefix = String(layout[..<range.lowerBound])
                var prefix = Self.normalized(rawPrefix)
                // 2026-11-14: a bracketed name tag in front of the turn ([畑中十萌]「…」,
                // 【澪】「…」). Its fancy lettering is misread freely (【23？】, ［畑中十前】),
                // and a stray closer of the previous line may precede it.
                while let first = prefix.first, ")」』".contains(first) { prefix.removeFirst() }
                let bracketTag = !prefix.isEmpty && prefix.count <= 16
                    && ("[【".contains(prefix.first!) || "]】".contains(prefix.last!))
                    && !prefix.contains(where: { "「『(".contains($0) })
                let separated = rawPrefix.last?.isWhitespace == true
                let namePattern = separated
                    ? "^[\\p{Han}\\p{Katakana}\\p{Hiragana}A-Za-z0-9ー・]*$"
                    : "^[\\p{Han}\\p{Katakana}A-Za-z0-9ー・]*$"
                // Separated labels are ambiguous with narrative lines, even after OCR
                // replaces their only hiragana character. Keep unknown labels short.
                // Consult this provider's own indexes, never shared/global lookup state.
                let hiraganaLabel = separated && prefix.range(of: "[\\p{Hiragana}]", options: .regularExpression) != nil
                let knownPrefix = separated && (exact[prefix] != nil || looseExact[Self.looseKey(prefix)] != nil
                    || ambiguousExact.contains(prefix) || ambiguousLoose.contains(Self.looseKey(prefix)))
                let unsafeLabel = (separated && prefix.count > (hiraganaLabel ? 4 : 10)) || knownPrefix
                // ICU script extensions include punctuation: exclude it explicitly.
                if bracketTag || (prefix.count <= 20 && !unsafeLabel
                    && !prefix.contains(where: { "「」『』()（）。、！？!?".contains($0) })
                    && prefix.range(of: namePattern, options: .regularExpression) != nil) {
                    let dialogue = Self.normalized(String(layout[range.lowerBound...]))
                    // Open turns remain eligible for strict/fuzzy matching only;
                    // exactMatch's balance guard still protects the loose layer.
                    add(dialogue)
                    if Self.balanced(dialogue) { add(stripQuotes(dialogue)) }
                }
            }
        }
        return candidates
    }

    /// Bounded Levenshtein. Exits quickly if the threshold is already exceeded.
    private static func editDistanceWithin(_ a: String, _ b: String, limit: Int) -> Int? {
        let x = Array(a), y = Array(b)
        guard abs(x.count - y.count) <= limit else { return nil }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var next = Array(repeating: limit + 1, count: y.count + 1)
            next[0] = i
            let low = max(1, i - limit)
            let high = min(y.count, i + limit)
            if low > high { return nil }
            var rowMin = limit + 1
            for j in low...high {
                let cost = x[i-1] == y[j-1] ? 0 : 1
                next[j] = min(previous[j] + 1, next[j-1] + 1, previous[j-1] + cost)
                rowMin = min(rowMin, next[j])
            }
            if rowMin > limit { return nil }
            previous = next
        }
        let distance = previous[y.count]
        return distance <= limit ? distance : nil
    }

    private static func extractTranslation(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any] {
                for key in ["premt", "rengong", "人工翻译", "人工翻譯", "pretranslation", "translation"] {
                    if let value = dict[key] as? String, !value.isEmpty { return value }
                }
                for key in dict.keys.sorted() {
                    if let value = dict[key] as? String, !value.isEmpty { return value }
                }
                return nil
            }
            if let value = object as? String, !value.isEmpty { return value }
        }
        return raw.isEmpty ? nil : raw
    }
}
