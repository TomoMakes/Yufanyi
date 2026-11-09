import Foundation
import SQLite3
import Testing
@testable import ScreenTranslate

/// 2026-11-09 形近字容错（设置里开，默认关）：仁科 → 化科、っつーか → つつーか。
@Suite struct LunaLookAlikeTests {
    private func makeDatabase(_ rows: [(String, String)]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LunaLookAlikeTests-\(UUID().uuidString).sqlite")
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

    private let rows = [
        ("「……もしかして仁科さんに恋人が？」", "「……难道仁科先生有恋人了？」"),
        ("「っつーか」", "「话说」"),
        ("話に入る", "插话"),
        ("「あの、失礼ですが稀モノをお探しなのでしょうか？」", "「那个，不好意思，请问您是在找稀有之物吗？」"),
    ]

    @Test func swapsALookAlikeBackWhenEnabled() throws {
        let provider = LunaPretranslationProvider(path: try makeDatabase(rows), lookAlikeEnabled: true)
        #expect(try provider.translate(text: "「・・・・・・もしかして化科さんに恋人が?」", lineAlternates: [:])
            == "「……难道仁科先生有恋人了？」")
        #expect(try provider.translate(text: "「つつーか」", lineAlternates: [:]) == "「话说」")
    }

    @Test func offByDefault() throws {
        let provider = LunaPretranslationProvider(path: try makeDatabase(rows))
        let output = try provider.translate(text: "「つつーか」", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func exactRecordWinsOverSwaps() throws {
        let path = try makeDatabase([("「カード」", "「卡片」"), ("「力ード」", "「力量」")])
        let provider = LunaPretranslationProvider(path: path, lookAlikeEnabled: true)
        #expect(try provider.translate(text: "「カード」", lineAlternates: [:]) == "「卡片」")
    }

    @Test func swapsLandingOnDifferentTranslationsBlock() throws {
        // 「カ口」：口→ロ 得「カロ」，カ→力 得「力口」，两种译文，不猜
        let path = try makeDatabase([("「カロ」", "「卡罗」"), ("「力口」", "「力口」")])
        let provider = LunaPretranslationProvider(path: path, lookAlikeEnabled: true)
        let output = try provider.translate(text: "「カ口」", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func aKnownFirstLineIsStillTranslatedOnItsOwn() throws {
        let provider = LunaPretranslationProvider(path: try makeDatabase(rows), lookAlikeEnabled: true)
        let output = try provider.translate(text: "話に入る\n「あの、失礼ですが稀モノをお探しなのでしょうか？」", lineAlternates: [:])
        #expect(output == "插话\n\n「那个，不好意思，请问您是在找稀有之物吗？」")
    }
}
