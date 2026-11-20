import XCTest
@testable import ScreenTranslate

/// L10n의 모든 정적 프로퍼티가 빈 문자열이 아닌지 전수 검사한다.
/// UserDefaults 상태를 변경하므로 직렬 실행이 보장되어야 한다.
/// 유지보수: L10n에 새 static var 추가 시 allStaticStrings에도 반드시 추가할 것.
final class L10nTests: XCTestCase {

    private let appLanguageKey = "com.screentranslate.appLanguage"
    private var savedLanguage: String?

    override func setUp() {
        savedLanguage = UserDefaults.standard.string(forKey: appLanguageKey)
    }

    override func tearDown() {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: appLanguageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: appLanguageKey)
        }
    }

    // MARK: - 전수 검사

    func test_allStrings_notEmpty_english() {
        UserDefaults.standard.set("en", forKey: appLanguageKey)

        for (name, value) in allStaticStrings() {
            XCTAssertFalse(value.isEmpty, "L10n.\(name) 영어 값이 비어있다")
        }
    }

    func test_allStrings_notEmpty_korean() {
        UserDefaults.standard.set("ko", forKey: appLanguageKey)

        for (name, value) in allStaticStrings() {
            XCTAssertFalse(value.isEmpty, "L10n.\(name) 한국어 값이 비어있다")
        }
    }

    func test_allStrings_notEmpty_traditional() {
        UserDefaults.standard.set("zh-Hant", forKey: appLanguageKey)

        for (name, value) in allStaticStrings() {
            XCTAssertFalse(value.isEmpty, "L10n.\(name) 繁体值为空")
        }
    }

    func test_functionStrings_notEmpty_english() {
        UserDefaults.standard.set("en", forKey: appLanguageKey)

        for (name, value) in functionStrings() {
            XCTAssertFalse(value.isEmpty, "L10n.\(name) 영어 값이 비어있다")
        }
    }

    func test_functionStrings_notEmpty_korean() {
        UserDefaults.standard.set("ko", forKey: appLanguageKey)

        for (name, value) in functionStrings() {
            XCTAssertFalse(value.isEmpty, "L10n.\(name) 한국어 값이 비어있다")
        }
    }

    func test_english_korean_differ() {
        // 영어와 한국어 값이 서로 다른지 확인 (같으면 번역 누락 의심)
        UserDefaults.standard.set("en", forKey: appLanguageKey)
        let enStrings = allStaticStrings()

        UserDefaults.standard.set("ko", forKey: appLanguageKey)
        let koStrings = allStaticStrings()

        for (en, ko) in zip(enStrings, koStrings) {
            XCTAssertEqual(en.0, ko.0, "키 순서가 일치해야 한다")
            // "OK" 같은 경우 영어/한국어가 다를 수 있으므로 경고만 (실패는 아님)
            if en.1 == ko.1 {
                // 의도적으로 동일할 수 있는 항목 (고유명사, 기술 용어 등)
                let allowedSameKeys: Set<String> = [
                    "ocrEngineName", "translationEngineName",
                    "copied",  // "Copied" 같은 짧은 표현
                ]
                // 预翻译 for Mac 已删韩语界面（2026-11-06），之后新加的文字韩语位置直接填英文
                let addedAfterKoreanRemoved = en.0.hasPrefix("luna") || en.0.hasPrefix("hitRate")
                    || en.0.hasPrefix("showHitRate") || en.0.hasPrefix("autoHideLiveBorder") || en.0.hasPrefix("aboutBasedOn") || en.0.hasPrefix("contact") || en.0.hasPrefix("aboutUpstream")
                if !allowedSameKeys.contains(en.0) && !addedAfterKoreanRemoved {
                    XCTFail("L10n.\(en.0) 영어와 한국어가 동일 (\"\(en.1)\") — 번역 누락 가능성")
                }
            }
        }
    }

    // MARK: - 문자열 목록

    /// L10n의 모든 static var를 (이름, 값) 쌍으로 반환한다.
    /// L10n에 새 static var를 추가하면 여기에도 추가해야 한다.
    private func allStaticStrings() -> [(String, String)] {
        [
            // Menu Bar
            ("translate", L10n.translate),
            ("recentTranslations", L10n.recentTranslations),
            ("noHistory", L10n.noHistory),
            ("showAll", L10n.showAll),
            ("aboutApp", L10n.aboutApp),
            ("settingsMenu", L10n.settingsMenu),
            ("checkForUpdates", L10n.checkForUpdates),
            ("quit", L10n.quit),

            // Popup
            ("recognizing", L10n.recognizing),
            ("translating", L10n.translating),
            ("showOriginal", L10n.showOriginal),
            ("copied", L10n.copied),
            ("copy", L10n.copy),
            ("close", L10n.close),
            ("lowConfidence", L10n.lowConfidence),
            ("originalText", L10n.originalText),

            // Settings
            ("generalSection", L10n.generalSection),
            ("appLanguageLabel", L10n.appLanguageLabel),
            ("translationSection", L10n.translationSection),
            ("sourceLanguageLabel", L10n.sourceLanguageLabel),
            ("autoDetect", L10n.autoDetect),
            ("targetLanguageLabel", L10n.targetLanguageLabel),
            ("ocrEngine", L10n.ocrEngine),
            ("translationEngine", L10n.translationEngine),
            ("shortcutSection", L10n.shortcutSection),
            ("translationShortcut", L10n.translationShortcut),
            ("ocrEngineName", L10n.ocrEngineName),
            ("translationEngineName", L10n.translationEngineName),
            ("swapLanguages", L10n.swapLanguages),
            ("launchAtLogin", L10n.launchAtLogin),
            ("languagePackNotInstalled", L10n.languagePackNotInstalled),
            ("confirm", L10n.confirm),
            ("download", L10n.download),
            ("downloading", L10n.downloading),
            ("downloadingHint", L10n.downloadingHint),
            ("later", L10n.later),
            ("backgroundNoticeTitle", L10n.backgroundNoticeTitle),
            ("backgroundNoticeBody", L10n.backgroundNoticeBody),
            ("liveWaitingForText", L10n.liveWaitingForText),
            ("liveSourcePackMissing", L10n.liveSourcePackMissing),
            ("liveToolbarLabel", L10n.liveToolbarLabel),
            ("liveResizeHelp", L10n.liveResizeHelp),
            ("stopLiveTranslation", L10n.stopLiveTranslation),
            ("liveTranslateMenu", L10n.liveTranslateMenu),
            ("liveTranslateFeature", L10n.liveTranslateFeature),
            ("betaSection", L10n.betaSection),
            ("liveTranslateDesc", L10n.liveTranslateDesc),
            ("liveTranslateShortcut", L10n.liveTranslateShortcut),
            ("showMenuBarIcon", L10n.showMenuBarIcon),
            ("showMenuBarIconHelp", L10n.showMenuBarIconHelp),
            ("menuBarIconDesc", L10n.menuBarIconDesc),
            ("menuBarIconHiddenDesc", L10n.menuBarIconHiddenDesc),
            ("menuBarIconMissing", L10n.menuBarIconMissing),
            ("showHitRateInMenuBar", L10n.showHitRateInMenuBar),
            ("showHitRateInMenuBarDesc", L10n.showHitRateInMenuBarDesc),
            ("autoHideLiveBorder", L10n.autoHideLiveBorder),
            ("autoHideLiveBorderDesc", L10n.autoHideLiveBorderDesc),
            ("hitRateLowWarning", L10n.hitRateLowWarning),
            ("lunaLibrarySection", L10n.lunaLibrarySection),
            ("lunaUseToggle", L10n.lunaUseToggle),
            ("lunaLibraryEmpty", L10n.lunaLibraryEmpty),
            ("lunaLibraryImport", L10n.lunaLibraryImport),
            ("lunaLibraryImportPanel", L10n.lunaLibraryImportPanel),
            ("lunaLibraryRemove", L10n.lunaLibraryRemove),
            ("lunaLibraryUse", L10n.lunaLibraryUse),
            ("lunaLibraryHelp", L10n.lunaLibraryHelp),
            ("lunaLookAlikeToggle", L10n.lunaLookAlikeToggle),
            ("lunaLookAlikeDesc", L10n.lunaLookAlikeDesc),
            ("lunaLibraryRemoveTitle", L10n.lunaLibraryRemoveTitle),
            ("lunaLibraryImportFailed", L10n.lunaLibraryImportFailed),
            ("lunaLibraryNotLuna", L10n.lunaLibraryNotLuna),
            ("lunaLibraryMissing", L10n.lunaLibraryMissing),
            ("lunaFileMissing", L10n.lunaFileMissing),
            ("lunaNotStandard", L10n.lunaNotStandard),
            ("lunaNoRows", L10n.lunaNoRows),
            ("aboutBasedOn", L10n.aboutBasedOn),
            ("contactAuthor", L10n.contactAuthor),
            ("contactWindowTitle", L10n.contactWindowTitle),
            ("contactIntro", L10n.contactIntro),
            ("contactSocialDetail", L10n.contactSocialDetail),
            ("contactCopyName", L10n.contactCopyName),
            ("contactQuarkDetail", L10n.contactQuarkDetail),
            ("contactCopyGroupID", L10n.contactCopyGroupID),
            ("contactGitHubTitle", L10n.contactGitHubTitle),
            ("contactGitHubDetail", L10n.contactGitHubDetail),
            ("contactEmailTitle", L10n.contactEmailTitle),
            ("contactOpen", L10n.contactOpen),
            ("contactDownload", L10n.contactDownload),
            ("contactReportIssue", L10n.contactReportIssue),
            ("contactWriteEmail", L10n.contactWriteEmail),
            ("aboutUpstreamLink", L10n.aboutUpstreamLink),
            ("hideMenuBarIconTitle", L10n.hideMenuBarIconTitle),
            ("hideMenuBarIconMessage", L10n.hideMenuBarIconMessage),
            ("hideMenuBarIconConfirm", L10n.hideMenuBarIconConfirm),
            ("openHistory", L10n.openHistory),

            // API Keys
            ("apiKeysSection", L10n.apiKeysSection),
            ("enterApiKey", L10n.enterApiKey),
            ("apiKeyRequired", L10n.apiKeyRequired),
            ("apiKeySaved", L10n.apiKeySaved),
            ("clear", L10n.clear),
            ("invalidRequest", L10n.invalidRequest),
            ("apiKeyInvalid", L10n.apiKeyInvalid),
            ("quotaExceeded", L10n.quotaExceeded),
            ("regionLabel", L10n.regionLabel),
            ("regionPlaceholder", L10n.regionPlaceholder),

            // Advanced
            ("autoCopyToClipboard", L10n.autoCopyToClipboard),
            ("autoCopyToClipboardDesc", L10n.autoCopyToClipboardDesc),
            ("advancedSection", L10n.advancedSection),
            ("ocrTextPreprocessing", L10n.ocrTextPreprocessing),
            ("ocrTextPreprocessingDesc", L10n.ocrTextPreprocessingDesc),

            // History
            ("translationHistory", L10n.translationHistory),
            ("deleteAll", L10n.deleteAll),
            ("copyTranslation", L10n.copyTranslation),
            ("copyOriginal", L10n.copyOriginal),
            ("delete", L10n.delete),
            ("deleteAllHistory", L10n.deleteAllHistory),
            ("cancel", L10n.cancel),
            ("deleteAllConfirmation", L10n.deleteAllConfirmation),
            ("noHistoryMessage", L10n.noHistoryMessage),
            ("translatedText", L10n.translatedText),
            ("selectRecord", L10n.selectRecord),

            // Permission
            ("permissionRequired", L10n.permissionRequired),
            ("permissionDescription", L10n.permissionDescription),
            ("openSystemSettings", L10n.openSystemSettings),

            // Onboarding
            ("onboardingWelcome", L10n.onboardingWelcome),
            ("onboardingShortcutTitle", L10n.onboardingShortcutTitle),
            ("onboardingShortcutDesc", L10n.onboardingShortcutDesc),
            ("onboardingFlow1", L10n.onboardingFlow1),
            ("onboardingFlow2", L10n.onboardingFlow2),
            ("onboardingFlow3", L10n.onboardingFlow3),
            ("onboardingChangeHint", L10n.onboardingChangeHint),
            ("onboardingLangTitle", L10n.onboardingLangTitle),
            ("onboardingLangAutoSet", L10n.onboardingLangAutoSet),
            ("onboardingLangChoose", L10n.onboardingLangChoose),
            ("onboardingLangInstalled", L10n.onboardingLangInstalled),
            ("onboardingLangNotInstalled", L10n.onboardingLangNotInstalled),
            ("onboardingNext", L10n.onboardingNext),
            ("onboardingDone", L10n.onboardingDone),
            ("onboardingPermDesc", L10n.onboardingPermDesc),
            ("onboardingPermPrivacy1", L10n.onboardingPermPrivacy1),
            ("onboardingPermPrivacy2", L10n.onboardingPermPrivacy2),
            ("onboardingPermPrivacy3", L10n.onboardingPermPrivacy3),
            ("onboardingPermRestart", L10n.onboardingPermRestart),
            ("onboardingDownloadLater", L10n.onboardingDownloadLater),

            // Drag Translation (Beta)
            ("dragTranslate", L10n.dragTranslate),
            ("dragTranslateShortcut", L10n.dragTranslateShortcut),
            ("dragTranslateShortcutHelp", L10n.dragTranslateShortcutHelp),
            ("noSelectedText", L10n.noSelectedText),
            ("accessibilityPermissionRequired", L10n.accessibilityPermissionRequired),
            ("accessibilityPermissionDescription", L10n.accessibilityPermissionDescription),
            ("betaFeature", L10n.betaFeature),

            // Errors
            ("noTextFound", L10n.noTextFound),
            ("unsupportedLanguagePair", L10n.unsupportedLanguagePair),
            ("noTextToTranslate", L10n.noTextToTranslate),
            ("autoDetectFailedMessage", L10n.autoDetectFailedMessage),
            ("openSettings", L10n.openSettings),
            ("noDisplayFound", L10n.noDisplayFound),
            ("cropFailed", L10n.cropFailed),

            // Luna fallback
            ("lunaFallbackToggle", L10n.lunaFallbackToggle),
            ("lunaFallbackDesc", L10n.lunaFallbackDesc),
            ("lunaFallbackPrefix", L10n.lunaFallbackPrefix),
        ]
    }

    /// L10n의 함수형 문자열을 샘플 입력으로 검증한다.
    private func functionStrings() -> [(String, String)] {
        [
            ("languagePackMessage", L10n.languagePackMessage(name: "Korean")),
            ("captureError", L10n.captureError("test")),
            ("ocrFailed", L10n.ocrFailed("test")),
            ("translationFailed", L10n.translationFailed("test")),
            ("engineHttpError", L10n.engineHttpError("DeepL", status: 500)),
            ("liveLanguagePackMissing", L10n.liveLanguagePackMissing("Korean")),
            ("liveTranslateStopped", L10n.liveTranslateStopped("test")),
            ("featuresWithoutShortcut", L10n.featuresWithoutShortcut("Drag Translate")),
        ]
    }
}
