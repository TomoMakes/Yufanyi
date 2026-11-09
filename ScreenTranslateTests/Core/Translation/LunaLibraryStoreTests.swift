import Foundation
import SQLite3
import Testing
@testable import ScreenTranslate

/// 预翻译库导入制：复制进 App、目前 2 个、删除只删副本、0.1.0 旧路径自动导入
@MainActor @Suite struct LunaLibraryStoreTests {
    private let root: URL
    private let storeDir: URL
    private let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LunaLibraryStoreTests-\(UUID().uuidString)")
        storeDir = root.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "LunaLibraryStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeStore() -> LunaLibraryStore {
        LunaLibraryStore(directory: storeDir, defaults: defaults)
    }

    /// 建一个最小的 Luna 预翻译库；row 不同，内容就不同
    private func makeLunaDatabase(_ name: String, row: String = "こんにちは") throws -> URL {
        let url = root.appendingPathComponent("\(name).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE artificialtrans (source TEXT, machineTrans TEXT); INSERT INTO artificialtrans VALUES ('\(row)', '你好');"
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func importCopiesFileAndActivatesIt() throws {
        let store = makeStore()
        let source = try makeLunaDatabase("天秤")
        let result = try store.importDatabase(from: source)
        guard case .added(let library) = result else { Issue.record("应为新导入"); return }
        #expect(library.name == "天秤")
        #expect(store.activeID == library.id)
        let copy = try #require(store.activePath)
        #expect(copy.hasPrefix(storeDir.path))
        // 原文件删掉后副本仍在
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: copy))
    }

    @Test func refusesBeyondMaxCount() throws {
        let store = makeStore()
        for i in 0..<LunaLibraryStore.maxCount {
            try store.importDatabase(from: makeLunaDatabase("库\(i)", row: "行\(i)"))
        }
        #expect(!store.canImport)
        let extra = try makeLunaDatabase("多出来的", row: "多")
        #expect(throws: LunaLibraryStore.ImportError.full) { try store.importDatabase(from: extra) }
        #expect(store.libraries.count == LunaLibraryStore.maxCount)
    }

    @Test func sameFileImportedTwiceJustActivates() throws {
        let store = makeStore()
        let a = try makeLunaDatabase("A", row: "a")
        let b = try makeLunaDatabase("B", row: "b")
        let first = try store.importDatabase(from: a)
        try store.importDatabase(from: b)
        guard case .added(let libA) = first else { Issue.record("应为新导入"); return }
        let again = try store.importDatabase(from: a)
        #expect(again == .alreadyImported(libA))
        #expect(store.activeID == libA.id)
        #expect(store.libraries.count == 2)
    }

    @Test func rejectsNonLunaFile() throws {
        let store = makeStore()
        let text = root.appendingPathComponent("随便.sqlite")
        try Data("not a database".utf8).write(to: text)
        #expect(throws: LunaLibraryStore.ImportError.notLunaDatabase) { try store.importDatabase(from: text) }
        #expect(store.libraries.isEmpty)
    }

    @Test func removeDeletesOnlyCopyAndSwitchesActive() throws {
        let store = makeStore()
        let a = try makeLunaDatabase("A", row: "a")
        let b = try makeLunaDatabase("B", row: "b")
        try store.importDatabase(from: a)
        try store.importDatabase(from: b)
        let active = try #require(store.activeLibrary)
        let copy = store.path(of: active)
        store.remove(active)
        #expect(!FileManager.default.fileExists(atPath: copy))
        #expect(FileManager.default.fileExists(atPath: b.path))
        #expect(store.libraries.count == 1)
        #expect(store.activeLibrary?.name == "A")
        #expect(store.canImport)
    }

    @Test func persistsAcrossInstances() throws {
        let store = makeStore()
        try store.importDatabase(from: makeLunaDatabase("A", row: "a"))
        try store.importDatabase(from: makeLunaDatabase("B", row: "b"))
        store.activate(store.libraries[0])
        let reloaded = makeStore()
        #expect(reloaded.libraries.map(\.name) == ["A", "B"])
        #expect(reloaded.activeLibrary?.name == "A")
    }

    @Test func migratesLegacyPathOnce() throws {
        let legacy = try makeLunaDatabase("旧版选的库")
        defaults.set(legacy.path, forKey: LunaLibraryStore.legacyPathKey)
        let store = makeStore()
        store.migrateLegacyPathIfNeeded()
        #expect(store.activeLibrary?.name == "旧版选的库")
        #expect(defaults.string(forKey: LunaLibraryStore.legacyPathKey) == nil)
    }

    @Test func legacyPathPointingNowhereIsDropped() {
        defaults.set(root.appendingPathComponent("不存在.sqlite").path, forKey: LunaLibraryStore.legacyPathKey)
        let store = makeStore()
        store.migrateLegacyPathIfNeeded()
        #expect(store.libraries.isEmpty)
        #expect(defaults.string(forKey: LunaLibraryStore.legacyPathKey) == nil)
    }
}
