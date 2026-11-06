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
    private let contextEnabled: Bool
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

    init(path: String, contextEnabled: Bool = true) {
        databasePath = path
        self.contextEnabled = contextEnabled
    }

    func translate(text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        try translate(text: text, lineAlternates: [:])
    }

    /// `lineAlternates`: Vision's lower-ranked readings keyed by a line of `text`
    /// (OCRResult.dialogueAlternates). Synchronous so the per-call state below
    /// cannot interleave with another call.
    func translate(text: String, lineAlternates: [String: [String]]) throws -> String {
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
            .flatMap { translateParagraph($0) }.joined(separator: "\n\n")
        if output.contains("［预翻译未命中］") {
            consecutiveMisses += 1
            if consecutiveMisses >= 2 { resetContext() }
        }
        return output
    }

    /// Live shortcut (2026-11-06): on AUTO a short line can leave the screen before two
    /// identical frames (~0.6 s apart) confirm it, so it is never shown. A frame whose whole
    /// text is one complete record - balanced quotes, ends with a closing quote or
    /// sentence-final mark, a unique strict or loose exact key - may be shown at once.
    /// A half-typed turn lacks its closing quote and keeps waiting. Never loads the
    /// database (the first translation does), so it cannot block a frame.
    func isCompleteExactHit(_ text: String) -> Bool {
        guard rows != nil else { return false }
        let key = Self.normalized(text)
        guard let last = key.last, "」』）)。！？!?…".contains(last), Self.balanced(key),
              key.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        if ambiguousExact.contains(key) { return false }
        if exact[key] != nil { return true }
        let loose = Self.looseKey(key)
        return !ambiguousLoose.contains(loose) && looseExact[loose] != nil
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
        guard !prefix.isEmpty, prefix.count <= 4,
              prefix.range(of: "^[\\p{L}\\p{N}ー・]+$", options: .regularExpression) != nil else { return nil }
        let body = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyKey = Self.normalized(body)
        guard bodyKey.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 8,
              !ambiguousExact.contains(bodyKey), let translation = exact[bodyKey] else { return nil }

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
              Self.normalized(text).unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 8
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

    private func fuzzyMatch(_ text: String) -> String? {
        guard let rows, !Self.hasUnclosedOpening(text) else { return nil }
        var scores: [String: Double] = [:]
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
                guard let distance = Self.editDistanceWithin(query, key, limit: limit) else { continue }
                let score = 1.0 - Double(distance) / Double(maxLength)
                let translation = rows[index].translation
                scores[translation] = max(scores[translation] ?? 0, score)
            }
        }
        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value >= 0.97,
              best.value - (ranked.dropFirst().first?.value ?? 0) >= 0.02 else { return nil }
        return best.key
    }

    private func lookup(_ text: String) -> String? {
        if queryVariants(text).contains(where: { ambiguousExact.contains($0) }) { return nil }
        if let hit = exactMatch(text) { return hit }
        if let hit = longVowelMatch(text) { return hit }
        if let hit = leadingSymbolMatch(text) { return hit }
        // A missing final quote is not permission to match an unrelated unquoted record.
        // Only restore one closing delimiter when the entire long body is an exact record.
        if !Self.balanced(text) {
            for query in queryVariants(text) where query.count >= 28 {
                if let first = query.first, let close = Self.quotePairs[first],
                   Self.balanced(query + String(close)), let hit = exact[query + String(close)] { return hit }
            }
            return Self.hasUnclosedOpening(text) ? nil : fuzzyMatch(text)
        }
        let repaired = repairMatch(text)
        if repaired.blocked { return nil }
        return repaired.translation ?? fuzzyMatch(text)
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

    // Real screenshots 2026-11-06 (0022, 0028): an opening 「……─── is split off and
    // misread (「……」」「．」」) or lost. Records that start with a quote plus an
    // ellipsis/dash run are indexed by the remaining body, closing quote included.
    private static let leadingRunCharacters = Set(".・•⋯…‥―─—–-")
    private var leadingSymbolIndex: [String: Set<String>] = [:]

    private static func leadingSymbolBody(ofRecord key: String) -> String? {
        let chars = Array(key)
        guard chars.count > 2, chars[0] == "「" || chars[0] == "『" else { return nil }
        var end = 1
        while end < chars.count && leadingRunCharacters.contains(chars[end]) { end += 1 }
        guard end > 1 else { return nil }
        return looseKey(String(chars[end...]))
    }

    private func leadingSymbolMatch(_ text: String) -> String? {
        let key = Self.normalized(text)
        guard let firstLetter = key.firstIndex(where: { $0.unicodeScalars.contains { CharacterSet.letters.contains($0) } }),
              firstLetter > key.startIndex else { return nil }
        let prefix = key[..<firstLetter]
        guard prefix.contains(where: { Self.leadingRunCharacters.contains($0) }),
              prefix.allSatisfy({ Self.leadingRunCharacters.contains($0) || "「」『』。、".contains($0) }) else { return nil }
        let body = String(key[firstLetter...])
        guard let close = body.last, close == "」" || close == "』",
              body.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 6,
              Self.balanced((close == "」" ? "「" : "『") + body) else { return nil }
        guard let translations = leadingSymbolIndex[Self.looseKey(body)], translations.count == 1,
              let translation = translations.first else { return nil }
        // A record without the leading run is a competing reading of the same text.
        let open: Character = close == "」" ? "「" : "『"
        if let plain = exact[String(open) + body], plain != translation { return nil }
        if ambiguousExact.contains(String(open) + body) { return nil }
        return translation
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
            throw TranslationError.translationFailed("找不到 Luna 预翻译文件，请重新选择")
        }
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw TranslationError.translationFailed("无法打开 SQLite：\(message)")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT source, machineTrans, rowid FROM artificialtrans ORDER BY rowid", -1, &statement, nil) == SQLITE_OK,
              let query = statement else {
            throw TranslationError.translationFailed("这不是标准 Luna 预翻译库：缺少 artificialtrans/source/machineTrans")
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
            guard !(seen[key]?.contains(translation) ?? false) else { return }
            seen[key, default: []].insert(translation)
            let loose = Self.looseKey(key)
            if Self.needsRepairIndex(key), let repair = Self.repairKey(key) { repairIndex[repair, default: []].append(result.count) }
            if let body = Self.leadingSymbolBody(ofRecord: key) { leadingSymbolIndex[body, default: []].insert(translation) }
            result.append(Entry(key: loose, strictKey: key, id: id, strictLength: key.count, translation: translation))
            if let prior = looseExact[loose], prior != translation {
                ambiguousLoose.insert(loose)
                looseExact.removeValue(forKey: loose)
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
            throw TranslationError.translationFailed("数据库中没有可用的日中对照记录")
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

    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0.value != 0x200B }
            .map(String.init).joined()
    }

    private static let ellipsisCharacters = CharacterSet(charactersIn: ".・•⋯")
    private static let dashCharacters = CharacterSet(charactersIn: "―─—–ー一-")
    private static let ellipsisPattern = try! NSRegularExpression(pattern: "[.・•⋯]{2,}|⋯")
    private static let dashPattern = try! NSRegularExpression(pattern: "[―─—–ー一-]{2,}")

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
                let prefix = Self.normalized(rawPrefix)
                let separated = rawPrefix.last?.isWhitespace == true
                let namePattern = separated
                    ? "^[\\p{Han}\\p{Katakana}\\p{Hiragana}A-Za-z0-9ー・]*$"
                    : "^[\\p{Han}\\p{Katakana}A-Za-z0-9ー・]*$"
                // Separated labels are ambiguous with narrative lines, even after OCR
                // replaces their only hiragana character. Keep unknown labels short.
                // Consult this provider's own indexes, never shared/global lookup state.
                let hiraganaLabel = separated && prefix.range(of: "[\\p{Hiragana}]", options: .regularExpression) != nil
                let knownPrefix = hiraganaLabel && (exact[prefix] != nil || looseExact[Self.looseKey(prefix)] != nil
                    || ambiguousExact.contains(prefix) || ambiguousLoose.contains(Self.looseKey(prefix)))
                let unsafeLabel = (separated && prefix.count > 4) || knownPrefix
                // ICU script extensions include punctuation: exclude it explicitly.
                if prefix.count <= 20, !unsafeLabel,
                   !prefix.contains(where: { "「」『』()（）。、！？!?".contains($0) }),
                   prefix.range(of: namePattern, options: .regularExpression) != nil {
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
