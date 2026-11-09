import Foundation

/// 本次实时翻译的预翻译命中统计（只在内存里，不上传、不写文件）。
/// 每出一句字幕记一次；同一句原文连续出现只算一次。
struct LunaHitStats: Equatable {
    static let missMarker = "［预翻译未命中］"
    /// 至少这么多句之后才判断命中率高低，避免开头几句就误报
    static let warningMinimumCount = 10
    /// 命中（含部分命中）低于这个比例时，提示库可能不对
    static let warningRate = 0.3

    private(set) var hits = 0
    private(set) var partials = 0
    private(set) var misses = 0
    private var lastSource: String?
    /// 上一句记的是不是未命中
    private var lastWasMiss = false

    var total: Int { hits + partials + misses }

    /// 命中率：完整命中 + 部分命中（部分命中至少有一段显示了译文）
    var rate: Double { total == 0 ? 0 : Double(hits + partials) / Double(total) }

    var showsLowRateWarning: Bool {
        total >= Self.warningMinimumCount && rate < Self.warningRate
    }

    /// 记录一句字幕。返回是否计入（同一句原文连续出现时不重复计）。
    /// correctsLastMiss：这句是画面没变时重新识别出来的，和上一句是同一句台词；
    /// 上一句记成了未命中，就撤掉那次，只按这次算，一句台词不记两次。
    @discardableResult
    mutating func record(source: String, output: String, correctsLastMiss: Bool = false) -> Bool {
        let key = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != lastSource else { return false }
        if correctsLastMiss, lastWasMiss, misses > 0 {
            misses -= 1
        }
        lastSource = key
        lastWasMiss = false
        if !output.contains(Self.missMarker) {
            hits += 1
        } else if Self.hasTranslatedPart(output) {
            partials += 1
        } else {
            misses += 1
            lastWasMiss = true
        }
        return true
    }

    /// 预翻译输出按段用空行连接，未命中的段以标记开头。
    /// 有一段不带标记，就说明这句至少有一段显示了译文。
    private static func hasTranslatedPart(_ output: String) -> Bool {
        output.components(separatedBy: "\n\n").contains { segment in
            !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !segment.contains(missMarker)
        }
    }

    /// 显示的一行，如「命中 80%」；还没有字幕时为 nil
    var summary: String? {
        guard total > 0 else { return nil }
        let percent = Int((rate * 100).rounded())
        return L10n.hitRateSummary(percent)
    }
}
