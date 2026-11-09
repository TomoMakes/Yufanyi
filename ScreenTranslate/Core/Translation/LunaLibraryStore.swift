import Foundation
import Observation
import SQLite3

/// 预翻译库列表（2026-11-07 定：导入制）。
/// 导入时复制一份进 App 自己的文件夹，原文件之后移走、改名、删掉都不影响；
/// 删除只删 App 里的副本。目前支持 2 个库，上限只在 `maxCount` 一处。
@MainActor @Observable
final class LunaLibraryStore {
    struct Library: Codable, Equatable, Identifiable {
        let id: String
        /// 显示名：导入时的文件名（不带扩展名）
        var name: String
        /// 副本在 `directory` 里的文件名
        let fileName: String
    }

    enum ImportResult: Equatable {
        case added(Library)
        /// 同一份库已经导入过，直接切换到它
        case alreadyImported(Library)
    }

    enum ImportError: LocalizedError, Equatable {
        case full
        case notLunaDatabase
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .full: L10n.lunaLibraryFull(LunaLibraryStore.maxCount)
            case .notLunaDatabase: L10n.lunaLibraryNotLuna
            case .copyFailed(let reason): L10n.lunaLibraryCopyFailed(reason)
            }
        }
    }

    nonisolated static let maxCount = 2
    nonisolated static let listKey = "com.yufanyi.lunaLibraries"
    nonisolated static let activeKey = "com.yufanyi.activeLunaLibrary"
    /// 0.1.0 只存一个路径（指向用户自己的文件），升级后自动导入一次
    nonisolated static let legacyPathKey = "com.screentranslate.lunaDatabasePath"

    static let shared = LunaLibraryStore()

    private(set) var libraries: [Library] = []
    private(set) var activeID: String?
    let directory: URL
    @ObservationIgnored private let defaults: UserDefaults

    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yufanyi.mac", isDirectory: true)
            .appendingPathComponent("预翻译库", isDirectory: true)
    }

    init(directory: URL = LunaLibraryStore.defaultDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.listKey),
           let saved = try? JSONDecoder().decode([Library].self, from: data) {
            // 副本被人从文件夹里删掉了的，不再列出
            libraries = saved.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }
        }
        let savedActive = defaults.string(forKey: Self.activeKey)
        activeID = libraries.contains { $0.id == savedActive } ? savedActive : libraries.first?.id
    }

    var activeLibrary: Library? { libraries.first { $0.id == activeID } }
    var activePath: String? { activeLibrary.map(path(of:)) }
    var canImport: Bool { libraries.count < Self.maxCount }

    func path(of library: Library) -> String {
        directory.appendingPathComponent(library.fileName).path
    }

    @discardableResult
    func importDatabase(from url: URL) throws(ImportError) -> ImportResult {
        let fm = FileManager.default
        if let existing = libraries.first(where: { fm.contentsEqual(atPath: url.path, andPath: path(of: $0)) }) {
            activate(existing)
            return .alreadyImported(existing)
        }
        guard canImport else { throw .full }
        guard Self.isLunaDatabase(at: url.path) else { throw .notLunaDatabase }

        let id = UUID().uuidString
        let fileName = "\(id).sqlite"
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: directory.appendingPathComponent(fileName))
        } catch {
            throw .copyFailed(error.localizedDescription)
        }
        let library = Library(id: id, name: url.deletingPathExtension().lastPathComponent, fileName: fileName)
        libraries.append(library)
        activeID = id
        save()
        return .added(library)
    }

    func activate(_ library: Library) {
        guard libraries.contains(library) else { return }
        activeID = library.id
        save()
    }

    /// 只删 App 里的副本，不碰用户原来的文件
    func remove(_ library: Library) {
        try? FileManager.default.removeItem(atPath: path(of: library))
        libraries.removeAll { $0.id == library.id }
        if activeID == library.id { activeID = libraries.first?.id }
        save()
    }

    /// 0.1.0 升级上来：把原来选的那个文件导入一次。成功后删掉旧路径，失败就留着下次再试。
    func migrateLegacyPathIfNeeded() {
        guard let path = defaults.string(forKey: Self.legacyPathKey) else { return }
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            defaults.removeObject(forKey: Self.legacyPathKey)
            return
        }
        if (try? importDatabase(from: URL(fileURLWithPath: path))) != nil {
            defaults.removeObject(forKey: Self.legacyPathKey)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(libraries) {
            defaults.set(data, forKey: Self.listKey)
        }
        defaults.set(activeID, forKey: Self.activeKey)
    }

    /// 能打开、并且有 Luna 预翻译的 artificialtrans 表（source、machineTrans 两列）
    nonisolated static func isLunaDatabase(at path: String) -> Bool {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            return false
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let ok = sqlite3_prepare_v2(db, "SELECT source, machineTrans FROM artificialtrans LIMIT 1", -1, &statement, nil) == SQLITE_OK
        sqlite3_finalize(statement)
        return ok
    }
}
