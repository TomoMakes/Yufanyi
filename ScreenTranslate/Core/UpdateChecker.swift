import AppKit
import Foundation
import Observation

/// 轻量 GitHub Releases 版本检查器：
/// - 启动后后台静默检查一次（之后每 24 小时检查一次），网络不通时完全静默、不打扰离线使用。
/// - 发现更高版本时更新 `availableUpdate`，菜单栏自动显示蓝色 NEW 徽章。
/// - 点击后弹出更新说明，同时提供「百度网盘下载」和「GitHub 下载」入口。
@MainActor @Observable
final class UpdateChecker {
    struct ReleaseInfo: Equatable {
        let version: String
        let tagName: String
        let htmlURL: URL
        let notes: String
    }

    static let shared = UpdateChecker()

    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/TomoMakes/Yufanyi/releases?per_page=5")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var availableUpdate: ReleaseInfo?
    private(set) var isChecking = false

    @ObservationIgnored private var backgroundTask: Task<Void, Never>?

    private init() {}

    func startBackgroundChecks() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                await self?.checkSilently()
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    func checkSilently() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        if let latest = try? await Self.fetchLatestRelease() {
            availableUpdate = Self.isNewer(latest.version, than: AppVersion.version) ? latest : nil
        }
    }

    func checkManually() {
        Task {
            if let cached = availableUpdate, Self.isNewer(cached.version, than: AppVersion.version) {
                presentUpdateAvailable(cached)
                return
            }
            guard !isChecking else { return }
            isChecking = true
            let result: Result<ReleaseInfo?, Error>
            do {
                result = .success(try await Self.fetchLatestRelease())
            } catch {
                result = .failure(error)
            }
            isChecking = false

            switch result {
            case .success(let latest?):
                if Self.isNewer(latest.version, than: AppVersion.version) {
                    availableUpdate = latest
                    presentUpdateAvailable(latest)
                } else {
                    availableUpdate = nil
                    presentUpToDate()
                }
            case .success(nil):
                availableUpdate = nil
                presentUpToDate()
            case .failure:
                presentCheckFailed()
            }
        }
    }

    // MARK: - Alerts

    private func presentUpdateAvailable(_ info: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.updateAvailableTitle
        alert.informativeText = L10n.updateAvailableMessage(
            latest: info.version,
            current: AppVersion.version,
            notes: info.notes
        )
        alert.addButton(withTitle: L10n.updateOpenBaiduPan)
        alert.addButton(withTitle: L10n.updateOpenGitHub)
        alert.addButton(withTitle: L10n.later)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(ContactInfo.baiduPanURL)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(info.htmlURL)
        default:
            break
        }
    }

    private func presentUpToDate() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.updateUpToDateTitle
        alert.informativeText = L10n.updateUpToDateMessage(AppVersion.version)
        alert.addButton(withTitle: L10n.confirm)
        alert.runModal()
    }

    private func presentCheckFailed() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.updateFailedTitle
        alert.informativeText = L10n.updateFailedMessage
        alert.addButton(withTitle: L10n.updateOpenBaiduPan)
        alert.addButton(withTitle: L10n.confirm)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(ContactInfo.baiduPanURL)
        }
    }

    // MARK: - Networking & Parsing

    private struct GitHubReleaseDTO: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
    }

    private nonisolated static func fetchLatestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: releasesAPIURL)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Yufanyi-Mac/\(AppVersion.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let releases = try JSONDecoder().decode([GitHubReleaseDTO].self, from: data)
        guard let first = releases.first(where: { $0.draft != true }),
              let url = URL(string: first.html_url) else {
            return nil
        }
        let version = normalizedVersion(first.tag_name)
        guard !version.isEmpty else { return nil }
        let notes = Self.trimmedNotes(first.body ?? "")
        return ReleaseInfo(version: version, tagName: first.tag_name, htmlURL: url, notes: notes)
    }

    nonisolated static func normalizedVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        return s
    }

    nonisolated static func isNewer(_ remote: String, than current: String) -> Bool {
        let r = versionComponents(remote)
        let c = versionComponents(current)
        guard !r.isEmpty, !c.isEmpty else { return false }
        let count = max(r.count, c.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv != cv { return rv > cv }
        }
        return false
    }

    private nonisolated static func versionComponents(_ raw: String) -> [Int] {
        normalizedVersion(raw)
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    private nonisolated static func trimmedNotes(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let preview = lines.prefix(6).joined(separator: "\n")
        return preview.count > 260 ? String(preview.prefix(260)) + "…" : preview
    }
}
