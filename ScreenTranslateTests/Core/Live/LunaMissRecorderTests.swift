import Foundation
import Testing
@testable import ScreenTranslate

/// 自动保存未命中画面：存图、写记录、去重、清理、开关
@Suite struct LunaMissRecorderTests {
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("miss-\(UUID().uuidString)", isDirectory: true)
    }

    private func miss(_ text: String, image: Bool = true) -> LunaMiss {
        LunaMiss(image: image ? TestImages.block(at: 0) : nil, text: text, alternates: [text: ["别的读法"]],
                 output: "\(LunaHitStats.missMarker)\n\(text)")
    }

    private func pngs(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
    }

    @Test func savesImageAndRecordUnderLibraryName() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = LunaMissRecorder(library: "闇色の魔珠", root: root, appVersion: "0.1.2", isEnabled: { true })
        #expect(recorder.write(miss("雨の音に法えている。")))
        let folder = root.appendingPathComponent("闇色の魔珠")
        #expect(recorder.folder == folder)
        let entries = LunaMissRecorder.entries(in: folder)
        #expect(entries.count == 1)
        #expect(entries[0].text == "雨の音に法えている。")
        #expect(entries[0].library == "闇色の魔珠")
        #expect(entries[0].appVersion == "0.1.2")
        #expect(entries[0].alternates == ["雨の音に法えている。": ["别的读法"]])
        #expect(pngs(in: folder) == [entries[0].image].compactMap { $0 })
        #expect(pngs(in: folder).count == 1)
    }

    @Test func sameLineIsSavedOnlyOnceEvenAcrossRuns() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { true })
        #expect(first.write(miss("「そうだった。君の名前は一」")))
        #expect(!first.write(miss("「そうだった。 君の名前は一」\n")))
        // 下一次实时翻译换了新的记录器，以前存过的句子也不再存
        let second = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { true })
        #expect(!second.write(miss("「そうだった。君の名前は一」")))
        #expect(second.write(miss("别的句子")))
        #expect(LunaMissRecorder.entries(in: first.folder).count == 2)
        #expect(pngs(in: first.folder).count == 2)
    }

    @Test func keepsOnlyTheLatestImages() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = LunaMissRecorder(library: "库", root: root, appVersion: "1", maxImages: 3, isEnabled: { true })
        for index in 1...5 { #expect(recorder.write(miss("第\(index)句"))) }
        let entries = LunaMissRecorder.entries(in: recorder.folder)
        #expect(entries.map(\.text) == ["第3句", "第4句", "第5句"])
        #expect(pngs(in: recorder.folder).sorted() == entries.compactMap(\.image).sorted())
        // 被清掉的句子再出现时可以重新存
        #expect(recorder.write(miss("第1句")))
    }

    @Test func doesNothingWhenSwitchedOff() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var enabled = false
        let recorder = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { enabled })
        recorder.record(miss("关着的时候"))
        recorder.flush()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        // 实时翻译中途打开开关，下一句就开始存
        enabled = true
        recorder.record(miss("打开以后"))
        recorder.flush()
        #expect(LunaMissRecorder.entries(in: recorder.folder).map(\.text) == ["打开以后"])
    }

    @Test func emptyTextIsNotSaved() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { true })
        #expect(!recorder.write(miss(" \n ")))
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test(arguments: [
        ("闇色の魔珠", "闇色の魔珠"), ("Money Parasite ～嘘つきな女～", "Money Parasite ～嘘つきな女～"),
        ("a/b:c", "a_b_c"), ("  ", "未命名"), ("..", "未命名"), ("", "未命名"),
    ])
    func folderNameIsSafe(library: String, expected: String) {
        #expect(LunaMissRecorder.folderName(for: library) == expected)
    }

    // MARK: 2026-11-14 不是台词的不存、读法略有不同的不重复存

    @Test func screensThatAreNotDialogueAreNotSaved() {
        #expect(!LunaMissRecorder.looksLikeDialogue("＋操作説明\n\n履歴ロード\n\n決定 B戻る"))
        #expect(!LunaMissRecorder.looksLikeDialogue("畑中＋萌\nマジックに心を奪われて\n\n2026/11/11 18時14分56秒"))
        #expect(!LunaMissRecorder.looksLikeDialogue("TLI"))
        #expect(!LunaMissRecorder.looksLikeDialogue("Astris\n\nLunaMacPatc"))
        #expect(LunaMissRecorder.looksLikeDialogue("「そう、完気が出たみたいで良かった」"))
        #expect(LunaMissRecorder.looksLikeDialogue("梶間"))
        #expect(LunaMissRecorder.looksLikeDialogue("私以外が否定した考えを\n\n嫌だ。\n\n「私は…別に"))

        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { true })
        #expect(!recorder.write(miss("＋操作説明\n\n履歴ロード\n\n決定 B戻る")))
        #expect(LunaMissRecorder.entries(in: recorder.folder).isEmpty)
        #expect(pngs(in: recorder.folder).isEmpty)
    }

    @Test func aSlightlyDifferentReadingOfTheSameLineIsNotSavedAgain() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { true })
        #expect(recorder.write(miss("「え…・・・・！」")))
        #expect(!recorder.write(miss("「え...・・！」")))
        #expect(recorder.write(miss("「桃密…..・・・ねぇ」")))
        #expect(!recorder.write(miss("「密…・・・・・ねぇ」")))
        #expect(recorder.write(miss("「ええ。庶民がいるならお近付きになりたいな・..・って所でしょうか？")))
        #expect(!recorder.write(miss("「ええ。庶民がいるならお近付きになりたいな・...・って所でしょうか？」")))
        // 另一句照常存
        #expect(recorder.write(miss("「密です」")))
        // 换了记录器（下一次实时翻译）也认得
        let second = LunaMissRecorder(library: "库", root: root, appVersion: "1", isEnabled: { true })
        #expect(!second.write(miss("「桃密・・・ねぇ」")))
        #expect(LunaMissRecorder.entries(in: recorder.folder).count == 4)
    }
}

/// 「复制问题说明」的文字。不切界面语言（别的测试在并行读它），期望值用同一套界面文字拼。
@Suite struct LunaFeedbackReportTests {
    private func entry(_ text: String) -> LunaMissRecorder.Entry {
        .init(time: "2026-11-14T10:00:00Z", appVersion: "0.1.2", library: "闇色の魔珠", text: text,
              alternates: [:], output: "", image: nil)
    }

    @Test func listsLibraryVersionsRateAndLatestLines() {
        var stats = LunaHitStats()
        for index in 0..<7 { stats.record(source: "命中\(index)", output: "译文") }
        for index in 0..<3 { stats.record(source: "漏\(index)", output: "\(LunaHitStats.missMarker)\n漏") }
        let entries = (1...12).map { entry("第\($0)句") } + [entry("两行的\n句子")]
        let text = LunaFeedbackReport.text(library: "闇色の魔珠", rowCount: 24228, appVersion: "0.1.2",
                                           systemVersion: "26.1", stats: stats, entries: entries)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.count == 15)
        #expect(lines[0] == L10n.feedbackTitle)
        #expect(lines[1] == L10n.feedbackLibrary("闇色の魔珠", rows: 24228))
        #expect(lines[1].contains("闇色の魔珠") && lines[1].contains("24228"))
        #expect(lines[2] == L10n.feedbackVersions(app: "0.1.2", system: "26.1"))
        #expect(lines[3] == L10n.feedbackHitRate(percent: 70, total: 10, missed: 3))
        #expect(lines[4] == L10n.feedbackMissHeader(shown: 10, total: 13))
        // 只列最近 10 句，旧的在前；识别出的换行用 ↵ 标出
        #expect(lines[5] == "1. 第4句")
        #expect(lines[14] == "10. 两行的 ↵ 句子")
    }

    @Test func worksWithoutStatsOrSavedLines() {
        let text = LunaFeedbackReport.text(library: nil, rowCount: nil, appVersion: "0.1.2",
                                           systemVersion: "26.1", stats: nil, entries: [])
        #expect(text.components(separatedBy: "\n") == [
            L10n.feedbackTitle, L10n.feedbackNoLibrary, L10n.feedbackVersions(app: "0.1.2", system: "26.1"),
            L10n.feedbackNoMisses,
        ])
    }
}
