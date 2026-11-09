import Foundation
import SQLite3
import Testing
@testable import ScreenTranslate

/// 2026-11-09 实拍（色ドリ撫子）：长句认错 2 个字（貴方のことは→貴方の5点は、
/// 注音压字 空木→塾米）原来判未命中。34 字起、字数相同、只差 2 个字、
/// 4 个字以内没有别的译文时才接受。
@Suite struct LunaTwoEditTests {
    private func makeDatabase(_ rows: [(String, String)]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LunaTwoEditTests-\(UUID().uuidString).sqlite")
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

    private let ohisashi = "「ふふ、実は私も貴方のことは非常によく伺っておりますのでお相子ですね」"
    private let utsugi = "「お見掛けしたのはまさに帝都大のすぐ近くです。空木神社ってご存知ですか？」"

    @Test func twoMisreadCharactersInALongTurnMatch() throws {
        let path = try makeDatabase([
            (ohisashi, "「呵呵，其实我也经常听她提起你的事，彼此彼此呢」"),
            (utsugi, "「我看到的地方就在帝大旁边。您知道空木神社吗？」"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        #expect(try provider.translate(text: "「ふふ、実は私も貴方の5点は非常によく\n伺っておりますのでお相子ですね」", lineAlternates: [:])
            == "「呵呵，其实我也经常听她提起你的事，彼此彼此呢」")
        #expect(try provider.translate(text: "「お見掛けしたのはまさに帝都大のすぐ近くです。\n塾米神社ってご存知ですか？」", lineAlternates: [:])
            == "「我看到的地方就在帝大旁边。您知道空木神社吗？」")
    }

    @Test func aCloseRecordWithAnotherTranslationBlocks() throws {
        let path = try makeDatabase([
            ("鵜飼さんと共にそこに足を踏み入れた瞬間、その余りの壮麗さに私は息を呑んでしまった。", "与鹈饲先生一同踏入那里的瞬间，那过分的壮丽让我屏住了呼吸。"),
            ("紫鶴さんと共にそこに足を踏み入れた瞬間、その余りの壮麗さに私は息を呑んでしまった。", "与紫鹤先生一同踏入那里的瞬间，那过分的壮丽让我屏住了呼吸。"),
        ])
        let provider = LunaPretranslationProvider(path: path)
        // 名字认成了别的字，又另错一个字：两条都在 4 个字以内，不猜
        let output = try provider.translate(text: "鵜鶴さんと共にそこに足を踏み入れた瞬間、その余りの壮麗さに私は息を呑んでしまつた。", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func shortTurnsDoNotGetTwoErrors() throws {
        let path = try makeDatabase([("「お久し振りです、お元気そうで何よりです」", "「好久不见，您看起来精神很好」")])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "「お久し振りです、お気気そうで何よりてす」", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func extraCharactersAreNotSwallowed() throws {
        let path = try makeDatabase([(ohisashi, "「呵呵，其实我也经常听她提起你的事，彼此彼此呢」")])
        let provider = LunaPretranslationProvider(path: path)
        // 多出 2 个字（不是认错）不走这条
        let output = try provider.translate(text: "「ふふ、実は私も貴方のことは非常によくよく伺っておりますのでお相子ですねえ」", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }

    @Test func threeMisreadCharactersDoNotMatch() throws {
        let path = try makeDatabase([(ohisashi, "「呵呵，其实我也经常听她提起你的事，彼此彼此呢」")])
        let provider = LunaPretranslationProvider(path: path)
        let output = try provider.translate(text: "「ふふ、実は私も貴方の5点は非常によく伺っておりますのでお相手ですね」", lineAlternates: [:])
        #expect(output.hasPrefix("［预翻译未命中］"))
    }
}
