import Foundation

/// 「复制问题说明」的那段文字（2026-11-14 定）：纯文字，能直接贴到邮件、私信、评论里。
/// 只写库名、版本、命中率和 App 读到的未命中句子，不带任何个人信息。
nonisolated enum LunaFeedbackReport {
    /// 评论区一般有字数限制，句子只列最近这么多
    static let defaultLineLimit = 10

    static func text(library: String?, rowCount: Int?, appVersion: String, systemVersion: String,
                     stats: LunaHitStats?, entries: [LunaMissRecorder.Entry],
                     lineLimit: Int = defaultLineLimit) -> String {
        var lines = [L10n.feedbackTitle]
        lines.append(library.map { L10n.feedbackLibrary($0, rows: rowCount) } ?? L10n.feedbackNoLibrary)
        lines.append(L10n.feedbackVersions(app: appVersion, system: systemVersion))
        if let stats, stats.total > 0 {
            lines.append(L10n.feedbackHitRate(percent: Int((stats.rate * 100).rounded()),
                                              total: stats.total, missed: stats.total - stats.hits))
        }
        let recent = entries.suffix(max(1, lineLimit))
        if recent.isEmpty {
            lines.append(L10n.feedbackNoMisses)
        } else {
            lines.append(L10n.feedbackMissHeader(shown: recent.count, total: entries.count))
            for (index, entry) in recent.enumerated() {
                // 一句占一行：识别出的换行用 ↵ 标出来，换行位置本身也是线索
                let text = entry.text.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ↵ ")
                lines.append("\(index + 1). \(text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
