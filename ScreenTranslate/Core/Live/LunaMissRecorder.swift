import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 一句最终没命中的台词：App 当时识别的那块画面，加上识别出的字。
nonisolated struct LunaMiss: @unchecked Sendable {
    var image: CGImage?
    /// 送去查库的文字（Luna 用的 dialogueText）
    var text: String
    var alternates: [String: [String]]
    /// 字幕条上显示的内容（带未命中标记）
    var output: String
}

nonisolated protocol LunaMissRecording: AnyObject {
    func record(_ miss: LunaMiss)
}

/// 自动保存未命中画面（2026-11-14 定）：方便试用的人反馈问题，不用自己截图。
/// 桌面「预翻译问题反馈/<库名>/」里每句存一张 PNG，另有一份「记录.jsonl」。
/// 只在本机，不上传；默认关，设置里开。同一句只存一次，每个库最多留 `maxImages` 张。
nonisolated final class LunaMissRecorder: LunaMissRecording, @unchecked Sendable {
    struct Entry: Codable, Equatable {
        var time: String
        var appVersion: String
        var library: String
        var text: String
        var alternates: [String: [String]]
        var output: String
        /// 同一文件夹里的图片文件名；存图失败时为 nil
        var image: String?
    }

    nonisolated static let enabledKey = "com.yufanyi.recordLunaMisses"
    nonisolated static let logFileName = "记录.jsonl"
    nonisolated static let defaultMaxImages = 500

    nonisolated static var defaultRoot: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(L10n.missFolderName, isDirectory: true)
    }

    /// 库名当文件夹名：去掉路径里不能用的字符
    nonisolated static func folderName(for library: String) -> String {
        let cleaned = library.map { "/:\\".contains($0) || $0.isNewline ? "_" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.allSatisfy({ $0 == "." }) ? "未命名" : name
    }

    nonisolated static func folder(for library: String, root: URL = defaultRoot) -> URL {
        root.appendingPathComponent(folderName(for: library), isDirectory: true)
    }

    let folder: URL
    private let library: String
    private let appVersion: String
    private let maxImages: Int
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.yufanyi.missRecorder", qos: .utility)
    /// 已存过的句子（去掉空白、省略号长短统一后），含以前几次留下的，按存入顺序；只在 queue 上读写
    private var seen: [String]?
    private var counter = 0

    init(library: String, root: URL = LunaMissRecorder.defaultRoot, appVersion: String,
         maxImages: Int = LunaMissRecorder.defaultMaxImages,
         isEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: LunaMissRecorder.enabledKey) },
         now: @escaping () -> Date = Date.init) {
        self.library = library
        folder = Self.folder(for: library, root: root)
        self.appVersion = appVersion
        self.maxImages = max(1, maxImages)
        self.isEnabled = isEnabled
        self.now = now
    }

    /// 开关每次现查：实时翻译中途打开也立刻生效。写盘放后台，不拖慢字幕。
    func record(_ miss: LunaMiss) {
        guard isEnabled() else { return }
        queue.async { [self] in _ = write(miss) }
    }

    /// 等后台写完（测试、复制问题说明前用）
    func flush() { queue.sync {} }

    /// 返回是否新存了一条。不是台词的画面不存；同一句已经存过（读法只差一两个字也算）就不再存。
    @discardableResult
    func write(_ miss: LunaMiss) -> Bool {
        let key = Self.key(miss.text)
        guard !key.isEmpty, Self.looksLikeDialogue(miss.text) else { return false }
        if seen == nil { seen = Self.entries(in: folder).map { Self.key($0.text) } }
        guard seen?.contains(where: { Self.isSameLine($0, key) }) == false else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch { return false }

        let date = now()
        counter += 1
        var imageName: String?
        if let image = miss.image {
            // 同一秒里不同记录器（两次实时翻译）也不能重名
            var name = Self.fileStamp.string(from: date) + String(format: "-%03d.png", counter % 1000)
            while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                counter += 1
                name = Self.fileStamp.string(from: date) + String(format: "-%03d.png", counter % 1000)
            }
            if Self.writePNG(image, to: folder.appendingPathComponent(name)) { imageName = name }
        }
        let entry = Entry(time: ISO8601DateFormatter().string(from: date), appVersion: appVersion, library: library,
                          text: miss.text, alternates: miss.alternates, output: miss.output, image: imageName)
        guard Self.append(entry, in: folder) else { return false }
        seen?.append(key)
        prune()
        return true
    }

    /// 图片超过上限时删最旧的，并把记录里对应的行一起去掉
    private func prune() {
        var entries = Self.entries(in: folder)
        let withImage = entries.filter { $0.image != nil }.count
        guard withImage > maxImages else { return }
        var excess = withImage - maxImages
        var kept: [Entry] = []
        for entry in entries {
            if excess > 0, let image = entry.image {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(image))
                if let index = seen?.firstIndex(of: Self.key(entry.text)) { seen?.remove(at: index) }
                excess -= 1
            } else {
                kept.append(entry)
            }
        }
        entries = kept
        let encoder = Self.encoder
        let lines = entries.compactMap { try? encoder.encode($0) }.compactMap { String(data: $0, encoding: .utf8) }
        try? (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent(Self.logFileName),
                                                          atomically: true, encoding: .utf8)
    }

    // MARK: - 读写

    /// 按存入顺序（旧的在前）；读不懂的行跳过
    nonisolated static func entries(in folder: URL) -> [Entry] {
        guard let text = try? String(contentsOf: folder.appendingPathComponent(logFileName), encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private nonisolated static func append(_ entry: Entry, in folder: URL) -> Bool {
        guard var data = try? encoder.encode(entry) else { return false }
        data.append(0x0A)
        let url = folder.appendingPathComponent(logFileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            return FileManager.default.createFile(atPath: url.path, contents: data)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch { return false }
    }

    private nonisolated static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private nonisolated static let dotRuns = try! NSRegularExpression(pattern: "[….。・·•‥⋯]+")

    /// 去掉空白，省略号不管被读成几个什么点都算一样（「え…・・・・！」和「え...・・！」是同一句）
    nonisolated static func key(_ text: String) -> String {
        let compact = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map(String.init).joined()
        return dotRuns.stringByReplacingMatches(in: compact, range: NSRange(compact.startIndex..., in: compact),
                                                withTemplate: "…")
    }

    /// 2026-11-14：菜单、存档界面、章节标题、切到桌面时的画面也被存了下来（两个游戏约 20 条）。
    /// 台词至少有一个日文字，并且有一段以句末标点或收尾引号结束；
    /// 好几段都不带句末标点的是界面文字（＋操作説明 / 履歴ロード / 決定 B戻る）。
    nonisolated static func looksLikeDialogue(_ text: String) -> Bool {
        guard LunaPretranslationProvider.hasJapanese(text) else { return false }
        let blocks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard blocks.count >= 2 else { return true }
        return blocks.contains { block in
            guard let last = block.last else { return false }
            return "。！？!?」』）)…‥―─—".contains(last)
        }
    }

    /// 同一句台词的两次读法：一样，或只差一两个字（桃密／密、句尾少了引号）。
    /// 长句按一成放宽，上限 6 个字。
    nonisolated static func isSameLine(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let x = Array(a), y = Array(b)
        guard min(x.count, y.count) >= 4 else { return false }
        let limit = min(6, max(2, max(x.count, y.count) / 10))
        guard abs(x.count - y.count) <= limit else { return false }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var next = [i] + Array(repeating: 0, count: y.count)
            var rowMinimum = i
            for j in 1...y.count {
                next[j] = min(previous[j] + 1, next[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
                rowMinimum = min(rowMinimum, next[j])
            }
            if rowMinimum > limit { return false }
            previous = next
        }
        return previous[y.count] <= limit
    }

    private nonisolated static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
