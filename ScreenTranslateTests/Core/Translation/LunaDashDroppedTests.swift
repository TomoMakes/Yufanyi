import Foundation
import SQLite3
import Testing
@testable import ScreenTranslate

/// 2026-11-09 实机（色ドリ撫子）：Vision 把行尾的「───」整个漏读，
/// 「そう言って差し出された和綴じ本に───アウラはない。」读成两行、没有破折号，原来判未命中。
@Suite struct LunaDashDroppedTests {
    private func makeDatabase(_ rows: [(String, String)]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LunaDashDroppedTests-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE artificialtrans (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT, machineTrans TEXT, origin TEXT);", nil, nil, nil) == SQLITE_OK)
        for (source, translation) in rows {
            let json = "{\"rengong\": \"\(translation)\"}"
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(db, "INSERT INTO artificialtrans (source, machineTrans) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, source, -1, transient)
            sqlite3_bind_text(statement, 2, json, -1, transient)
            #expect(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        return url.path
    }

    @Test func lostDashRunStillMatches() throws {
        let path = try makeDatabase([
            ("そう言って差し出された和綴じ本に───アウラはない。", "说着递过来的和装本——没有灵韵。"),
            ("差し出された本にアウラはない。", "递过来的书上没有灵韵。"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        #expect(try provider.translate(text: "そう言って差し出された和綴じ本に\nアウラはない。", lineAlternates: [:])
            == "说着递过来的和装本——没有灵韵。")
        #expect(try provider.translate(text: "そう言って差し出された和綴じ本に─\nアウラはない。", lineAlternates: [:])
            == "说着递过来的和装本——没有灵韵。")
    }

    @Test func wrappedBeforeQuoteIsNotTreatedAsSpeakerPrefix() throws {
        let path = try makeDatabase([("もちろんそれは───『彼』のせいだ。", "当然那都是───『他』的错。")])
        let provider = LunaPretranslationProvider(path: path)
        #expect(try provider.translate(text: "もちろんそれは\n『彼』のせいだ。", lineAlternates: [:])
            == "当然那都是───『他』的错。")
    }

    @Test func conflictingRecordsBlock() throws {
        let path = try makeDatabase([
            ("それでも私はあの人を───信じたかった。", "即便如此我还是───想相信那个人。"),
            ("それでも私はあの人を──信じたかった。", "可我依然──想去相信他。"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "それでも私はあの人を\n信じたかった。", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func plainRecordWithOtherTranslationBlocks() throws {
        let path = try makeDatabase([
            ("それでも私はあの人を───信じたかった。", "即便如此我还是───想相信那个人。"),
            ("それでも私はあの人を信じたかった。", "可我依然想去相信他。"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        // 不带破折号的整句是库里另一条：照它翻；读出半截破折号时两条冲突，不猜。
        #expect(try provider.translate(text: "それでも私はあの人を信じたかった。", lineAlternates: [:])
            == "可我依然想去相信他。")
        let output = try provider.translate(text: "それでも私はあの人を─信じたかった。", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func shortTextIsNotMatched() throws {
        let path = try makeDatabase([("えっ───うそ。", "诶───骗人。")])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "えっうそ。", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    // MARK: 2026-11-15 点数读错，同时破折号整段丢（色ドリ撫子 库 52345）

    @Test func lostDashRunWithMiscountedDotsStillMatches() throws {
        let path = try makeDatabase([("あの女性と僕は……───他人みたいなものだ", "那位女性和我……───就像陌生人一样")])
        let provider = LunaPretranslationProvider(path: path)
        // 实机读法：六个点读成七个，「───」整段没读出来
        #expect(try provider.translate(text: "あの女性と僕は....... 他人みたいなものだ", lineAlternates: [:])
            == "那位女性和我……───就像陌生人一样")
        #expect(try provider.translate(text: "あの女性と僕は・・・・・・・他人みたいなものだ", lineAlternates: [:])
            == "那位女性和我……───就像陌生人一样")
    }

    @Test func miscountedDotsWithConflictingDashRecordsBlock() throws {
        let path = try makeDatabase([
            ("それでも私はあの人を……───信じたかった。", "即便如此我还是……───想相信那个人。"),
            ("それでも私はあの人を…………──信じたかった。", "可我依然…………──想去相信他。"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "それでも私はあの人を....... 信じたかった。", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func miscountedDotsPreferThePlainRecord() throws {
        let path = try makeDatabase([
            ("それでも私はあの人を……───信じたかった。", "即便如此我还是……───想相信那个人。"),
            ("それでも私はあの人を……信じたかった。", "可我依然……想去相信他。"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        // 不带破折号的那条本来就在库里：点数不同也照它翻，不去猜带破折号的那条
        #expect(try provider.translate(text: "それでも私はあの人を.......信じたかった。", lineAlternates: [:])
            == "可我依然……想去相信他。")
    }

    @Test func shortTextWithDotsIsNotMatched() throws {
        let path = try makeDatabase([("えっ……───うそ。", "诶……───骗人。")])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "えっ.......うそ。", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    // MARK: 2026-11-15 省略号读成别的圆点（色ドリ撫子 库 52489）

    @Test func ellipsisReadAsOtherRoundDotsStillMatches() throws {
        let path = try makeDatabase([("「もしかして……杙梛さんも見ました？」", "「难道……杙梛先生也看到了？」")])
        let provider = LunaPretranslationProvider(path: path)
        for dot in ["\u{00B7}", "\u{2027}", "\u{2219}", "\u{22C5}", "\u{FF65}", "\u{30FB}"] {
            let text = "「もしかして" + String(repeating: dot, count: 6) + "杙梛さんも見ました？」"
            #expect(try provider.translate(text: text, lineAlternates: [:]) == "「难道……杙梛先生也看到了？」", "圆点 \(dot.unicodeScalars.first!.value)")
        }
    }

    @Test func roundDotsDoNotHideDifferentTranslations() throws {
        let path = try makeDatabase([("「うん……」", "嗯……"), ("「うん…………」", "不……")])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "「うん\u{2027}\u{2027}\u{2027}」", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }
}
