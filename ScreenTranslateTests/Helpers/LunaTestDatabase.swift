import Foundation
import SQLite3
import Testing

/// 测试用的预翻译库：按给的顺序写入，rowid 从 1 开始连续。
enum LunaTestDatabase {
    static func make(_ rows: [(String, String)]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LunaTestDatabase-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE artificialtrans (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT, machineTrans TEXT, origin TEXT);", nil, nil, nil) == SQLITE_OK)
        for (source, translation) in rows {
            let json = String(data: try JSONSerialization.data(withJSONObject: ["rengong": translation]), encoding: .utf8)!
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
}
