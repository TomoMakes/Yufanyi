import Foundation
import Testing
@testable import ScreenTranslate

/// 界面繁体化（0.1.1）：默认语言跟系统、选繁体后显示繁体
@Suite(.serialized) struct L10nTraditionalTests {
    private let key = "com.screentranslate.appLanguage"

    @Test(arguments: [
        (["zh-Hant-TW"], "zh-Hant"), (["zh-Hant-HK"], "zh-Hant"), (["zh-TW"], "zh-Hant"), (["zh-HK"], "zh-Hant"),
        (["zh-Hans-CN"], "zh-Hans"), (["en-US", "zh-Hant-TW"], "zh-Hans"), (["ja-JP"], "zh-Hans"), ([], "zh-Hans"),
    ])
    func defaultLanguageFollowsSystemForTraditional(preferred: [String], expected: String) {
        #expect(L10n.defaultLanguage(for: preferred) == expected)
    }

    @Test func traditionalShowsTaiwanWording() {
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("zh-Hant", forKey: key)
        #expect(L10n.settingsMenu == "設定…")
        #expect(L10n.quit == "結束")
        #expect(L10n.hitRateSummary(80) == "命中 80%")
        #expect(L10n.hitRateLowWarning == "命中率低，可能選錯了庫")
        // App 名字保持简体（2026-11-09 定）
        #expect(L10n.aboutApp == "關於 预翻译 for Mac")

        UserDefaults.standard.set("zh-Hans", forKey: key)
        #expect(L10n.settingsMenu == "设置…")
    }
}
