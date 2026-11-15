import Foundation

/// 앱 전체 UI 문자열의 영어/한국어 로컬라이제이션.
/// UserDefaults에서 직접 읽어 nonisolated 컨텍스트(Error enum 등)에서도 안전하게 사용.
nonisolated enum L10n {
    private static var lang: String {
        UserDefaults.standard.string(forKey: "com.screentranslate.appLanguage") ?? defaultLanguage
    }

    /// 没选过界面语言时：系统是繁体中文（台湾、香港、澳门）就用繁体，其他一律简体（2026-11-09 定）
    static var defaultLanguage: String { defaultLanguage(for: Locale.preferredLanguages) }

    static func defaultLanguage(for preferred: [String]) -> String {
        guard let first = preferred.first?.lowercased() else { return "zh-Hans" }
        let traditional = ["zh-hant", "zh-tw", "zh-hk", "zh-mo"]
        return traditional.contains { first.hasPrefix($0) } ? "zh-Hant" : "zh-Hans"
    }

    /// tw：繁体（台湾用语），由简体经 OpenCC s2twp 转换后人工修订
    private static func s(_ en: String, ko: String, zh: String, tw: String) -> String {
        switch lang {
        case "zh-Hans": zh
        case "zh-Hant": tw
        case "ko": ko
        default: en
        }
    }

    // MARK: - Menu Bar

    static var translate: String { s("Screen Translate", ko: "화면 캡처 번역", zh: "截图翻译", tw: "截圖翻譯") }
    static var recentTranslations: String { s("Recent Translations", ko: "최근 번역", zh: "最近翻译", tw: "最近翻譯") }
    static var noHistory: String { s("No history", ko: "히스토리 없음", zh: "暂无记录", tw: "暫無記錄") }
    static var showAll: String { s("Show All...", ko: "모두 보기...", zh: "查看全部…", tw: "檢視全部…") }
    static var aboutApp: String { s("About 预翻译 for Mac", ko: "预翻译 for Mac 정보", zh: "关于 预翻译 for Mac", tw: "關於 预翻译 for Mac") }
    static var settingsMenu: String { s("Settings...", ko: "설정...", zh: "设置…", tw: "設定…") }
    static var settingsWindowTitle: String { s("Settings", ko: "설정", zh: "设置", tw: "設定") }
    static var checkForUpdates: String { s("Check for Updates...", ko: "업데이트 확인...", zh: "检查更新…", tw: "檢查更新…") }
    static var quit: String { s("Quit", ko: "종료", zh: "退出", tw: "結束") }

    // MARK: - Popup

    static var recognizing: String { s("Recognizing...", ko: "인식 중...", zh: "正在识别…", tw: "正在識別…") }
    static var translating: String { s("Translating...", ko: "번역 중...", zh: "正在翻译…", tw: "正在翻譯…") }
    static var showOriginal: String { s("Show Original", ko: "원문 보기", zh: "显示原文", tw: "顯示原文") }
    static var copied: String { s("Copied", ko: "복사됨", zh: "已复制", tw: "已複製") }
    static var copy: String { s("Copy", ko: "복사", zh: "复制", tw: "複製") }
    static var close: String { s("Close", ko: "닫기", zh: "关闭", tw: "關閉") }
    static var lowConfidence: String { s("Low recognition confidence", ko: "인식 정확도가 낮습니다", zh: "文字识别可信度较低", tw: "文字識別可信度較低") }
    static var translationSuperseded: String { s("Cancelled because another translation started.", ko: "다른 번역이 시작되어 취소되었습니다.", zh: "已取消：另一项翻译已开始。", tw: "已取消：另一項翻譯已開始。") }
    static var translationTimedOut: String { s("Translation timed out. Please try again.", ko: "번역 응답이 없어 시간이 초과되었습니다. 다시 시도해주세요.", zh: "翻译超时，请重试。", tw: "翻譯逾時，請重試。") }
    static var apiKeySaveFailed: String { s("Couldn't save the API key to Keychain. Unlock your keychain and try again.", ko: "API 키를 키체인에 저장하지 못했습니다. 키체인 잠금을 해제한 뒤 다시 시도해주세요.", zh: "无法将 API 密钥保存到钥匙串，请解锁钥匙串后重试。", tw: "無法將 API 金鑰儲存到鑰匙圈，請解鎖鑰匙圈後重試。") }
    static var historyNotPersisted: String { s("History can't be saved right now. Translations will be lost when the app quits.", ko: "지금은 히스토리를 저장할 수 없습니다. 앱을 종료하면 번역 기록이 사라집니다.", zh: "暂时无法保存历史记录，退出应用后本次翻译记录将丢失。", tw: "暫時無法儲存歷史記錄，結束 App 後本次翻譯記錄將丟失。") }
    static var originalText: String { s("Original", ko: "원문", zh: "原文", tw: "原文") }

    // MARK: - Quick Translate

    static var quickTranslate: String { s("Quick Translate", ko: "빠른 번역", zh: "快速翻译", tw: "快速翻譯") }
    static var quickTranslateShortcut: String { s("Quick Translate Shortcut", ko: "빠른 번역 단축키", zh: "快速翻译快捷键", tw: "快速翻譯快捷鍵") }
    static var quickTranslateShortcutHelp: String { s("Open a mini translation panel to type and translate text", ko: "텍스트를 입력하여 번역하는 미니 패널을 엽니다", zh: "打开小窗口，输入文字进行翻译", tw: "開啟小視窗，輸入文字進行翻譯") }
    static var inputPlaceholder: String { s("Type text to translate...", ko: "번역할 텍스트를 입력하세요...", zh: "输入要翻译的文字…", tw: "輸入要翻譯的文字…") }
    static var resultPlaceholder: String { s("Translation will appear here", ko: "번역 결과가 여기에 표시됩니다", zh: "译文将在这里显示", tw: "譯文將在這裡顯示") }
    static var quickTranslateHint: String { s("ESC: close  ·  Enter: translate  ·  ⇧Enter: new line  ·  ⌘/: swap", ko: "ESC: 닫기  ·  Enter: 번역  ·  ⇧Enter: 줄바꿈  ·  ⌘/: 언어 전환", zh: "ESC：关闭 · Enter：翻译 · ⇧Enter：换行 · ⌘/：交换语言", tw: "ESC：關閉 · Enter：翻譯 · ⇧Enter：換行 · ⌘/：交換語言") }
    static var sourceLanguageSelect: String { s("Source language", ko: "소스 언어 선택", zh: "原文语言", tw: "原文語言") }
    static var targetLanguageSelect: String { s("Target language", ko: "번역 대상 언어 선택", zh: "译文语言", tw: "譯文語言") }
    static var doubleCopyShortcut: String { s("⌘C+C", ko: "⌘C+C", zh: "⌘C+C", tw: "⌘C+C") }
    static var doubleCopyHelp: String { s("Press ⌘C twice quickly to translate copied text", ko: "⌘C를 빠르게 두 번 눌러 복사된 텍스트를 번역합니다", zh: "快速按两次 ⌘C，翻译复制的文字", tw: "快速按兩次 ⌘C，翻譯複製的文字") }
    static var noClipboardText: String { s("No text in clipboard. Please copy text first.", ko: "클립보드에 텍스트가 없습니다. 먼저 텍스트를 복사해주세요.", zh: "剪贴板中没有文字，请先复制文字。", tw: "剪貼簿中沒有文字，請先複製文字。") }

    // MARK: - Settings

    static var generalSection: String { s("General", ko: "일반", zh: "通用", tw: "通用") }
    static var generalTab: String { s("General", ko: "일반", zh: "通用", tw: "通用") }
    static var advancedTab: String { s("Advanced", ko: "고급", zh: "高级", tw: "進階") }
    static var engineSection: String { s("Translation Engine", ko: "번역 엔진", zh: "翻译引擎", tw: "翻譯引擎") }
    static var popupSection: String { s("Popup", ko: "팝업", zh: "字幕", tw: "字幕") }
    static var appSection: String { s("App", ko: "앱", zh: "应用", tw: "App") }
    static var otherSection: String { s("Other", ko: "기타", zh: "其他", tw: "其他") }
    static var appLanguageLabel: String { s("App Language", ko: "앱 언어", zh: "界面语言", tw: "介面語言") }
    static var translationSection: String { s("Translation", ko: "번역", zh: "翻译", tw: "翻譯") }
    static var sourceLanguageLabel: String { s("Source", ko: "원문", zh: "原文语言", tw: "原文語言") }
    static var autoDetect: String { s("Auto Detect", ko: "자동 감지", zh: "自动识别", tw: "自動識別") }
    static var targetLanguageLabel: String { s("Target", ko: "번역", zh: "译文语言", tw: "譯文語言") }
    static var ocrEngine: String { s("OCR Engine", ko: "OCR 엔진", zh: "文字识别引擎", tw: "文字識別引擎") }
    static var translationEngine: String { s("Translation Engine", ko: "번역 엔진", zh: "翻译引擎", tw: "翻譯引擎") }
    static var shortcutSection: String { s("Shortcut", ko: "단축키", zh: "快捷键", tw: "快捷鍵") }
    static var translationShortcut: String { s("Screen Translate Shortcut", ko: "화면 캡처 번역 단축키", zh: "截图翻译快捷键", tw: "截圖翻譯快捷鍵") }
    static var ocrEngineName: String { s("Apple Vision (Local)", ko: "Apple Vision (로컬)", zh: "Apple Vision（本地）", tw: "Apple Vision（本地）") }
    static var translationEngineName: String { s("Apple Translation (Local)", ko: "Apple Translation (로컬)", zh: "Apple 翻译（本地）", tw: "Apple 翻譯（本地）") }
    static var swapLanguages: String { s("Swap Languages", ko: "언어 교체", zh: "交换语言", tw: "交換語言") }
    static var launchAtLogin: String { s("Launch at Login", ko: "로그인 시 열기", zh: "登录时启动", tw: "登入時啟動") }
    static var languagePackNotInstalled: String { s("Language Pack Not Installed", ko: "언어팩 미설치", zh: "未安装语言包", tw: "未安裝語言包") }
    static var confirm: String { s("OK", ko: "확인", zh: "确定", tw: "確定") }
    static var download: String { s("Download", ko: "다운로드", zh: "下载", tw: "下載") }
    static var downloading: String { s("Downloading...", ko: "다운로드 중...", zh: "正在下载…", tw: "正在下載…") }
    static var downloadingHint: String { s("If a system popup appears, tap Download.\nIt may look frozen, but the download is in progress.\nThis can take a few minutes depending on your network.", ko: "시스템 팝업이 나타나면 다운로드를 눌러주세요.\n화면이 멈춘 것처럼 보일 수 있지만 정상적으로 진행 중입니다.\n네트워크 환경에 따라 몇 분 정도 걸릴 수 있습니다.", zh: "如果出现系统提示，请点击“下载”。\n下载期间界面可能暂时没有变化，请耐心等待。\n根据网络情况，可能需要几分钟。", tw: "如果出現系統提示，請點選「下載」。\n下載期間介面可能暫時沒有變化，請耐心等待。\n根據網路情況，可能需要幾分鐘。") }
    static var later: String { s("Later", ko: "나중에", zh: "稍后", tw: "稍後") }
    static var liveWaitingForText: String { s("Waiting for text…", ko: "자막을 기다리는 중…", zh: "等待文字出现…", tw: "等待文字出現…") }
    static var liveSourcePackMissing: String { s("This subtitle's language isn't downloaded yet. Download it in Settings → General to translate it live.", ko: "이 자막 언어의 언어팩이 아직 없습니다. 설정 → 일반에서 받으면 실시간으로 번역됩니다.", zh: "尚未下载这段字幕对应的语言包，请先到“设置 → 通用”中下载。", tw: "尚未下載這段字幕對應的語言包，請先到「設定 → 通用」中下載。") }
    static var liveToolbarLabel: String { s("LIVE · Drag to move", ko: "LIVE · 드래그해서 이동", zh: "实时翻译 · 拖动以移动", tw: "即時翻譯 · 拖移以移動") }
    static var liveResizeHelp: String { s("Drag to resize", ko: "드래그해서 크기 조절", zh: "拖动调整大小", tw: "拖移調整大小") }
    static var liveFullText: String { s("View full subtitle", ko: "전체 자막 보기", zh: "查看完整字幕", tw: "檢視完整字幕") }
    static var liveFullTextSnapshot: String { s("Subtitle snapshot", ko: "자막 스냅샷", zh: "当前字幕（快照）", tw: "目前字幕（快照）") }
    static var liveMoreText: String { s("More text · Move to the border and choose View full subtitle", ko: "더 보기 · 테두리에서 전체 자막 보기", zh: "还有内容 · 鼠标移到框边，点击“查看完整字幕”", tw: "還有內容 · 滑鼠移到框邊，點選「檢視完整字幕」") }
    static var stopLiveTranslation: String { s("Stop Live Translate", ko: "실시간 번역 중지", zh: "停止实时翻译", tw: "停止即時翻譯") }
    static var liveTranslateMenu: String { s("Live Translate", ko: "실시간 번역", zh: "实时翻译", tw: "即時翻譯") }
    static var liveTranslateFeature: String { s("Live Translate", ko: "실시간 번역", zh: "实时翻译", tw: "即時翻譯") }
    static var betaSection: String { s("Beta Features", ko: "베타 기능", zh: "测试功能", tw: "測試功能") }
    static var liveTranslateDesc: String { s("Keeps translating the text in an area you choose, like subtitles in a video. Uses Apple Translation only. Protected videos (such as Netflix) can't be captured. Uses more battery while running.", ko: "영상 자막처럼 고른 영역의 글자를 계속 번역합니다. Apple 번역만 쓰며, 넷플릭스 같은 보호된 영상은 캡처되지 않습니다. 켜 두는 동안 배터리를 더 씁니다.", zh: "持续识别并翻译框选区域内的文字。默认使用 Apple 翻译，也可在上方启用 Luna 预翻译库。无法截取 Netflix 等受保护的视频，运行时会增加耗电。", tw: "持續識別並翻譯框選區域內的文字。預設使用 Apple 翻譯，也可在上方啟用 Luna 預翻譯庫。無法擷取 Netflix 等受保護的影片，執行時會增加耗電。") }
    static var liveTranslateShortcut: String { s("Live Translate Shortcut", ko: "실시간 번역 단축키", zh: "实时翻译快捷键", tw: "即時翻譯快捷鍵") }
    static var backgroundNoticeTitle: String { s("预翻译 for Mac is running", ko: "预翻译 for Mac 실행 중", zh: "预翻译 for Mac 正在运行", tw: "预翻译 for Mac 正在執行") }
    static var backgroundNoticeBody: String { s("The menu bar icon is hidden. Use your shortcuts to translate, and open 预翻译 for Mac again to show Settings.", ko: "메뉴바 아이콘이 숨겨져 있습니다. 단축키로 번역하고, 설정은 预翻译 for Mac를 다시 열면 나타납니다.", zh: "菜单栏图标已隐藏。你仍可使用快捷键翻译，再次打开 预翻译 for Mac 即可进入设置。", tw: "選單列圖示已隱藏。你仍可使用快捷鍵翻譯，再次開啟 预翻译 for Mac 即可進入設定。") }
    static var showMenuBarIcon: String { s("Show Menu Bar Icon", ko: "메뉴바 아이콘 표시", zh: "显示菜单栏图标", tw: "顯示選單列圖示") }
    static var showMenuBarIconHelp: String { s("Show or hide the 预翻译 for Mac icon in the menu bar", ko: "메뉴바의 预翻译 for Mac 아이콘을 표시하거나 숨깁니다", zh: "显示或隐藏菜单栏中的 预翻译 for Mac 图标", tw: "顯示或隱藏選單列中的 预翻译 for Mac 圖示") }
    static var menuBarIconDesc: String { s("Shortcuts keep working when the icon is hidden.", ko: "아이콘을 숨겨도 단축키는 계속 작동합니다.", zh: "隐藏图标后，快捷键仍然可用。", tw: "隱藏圖示後，快捷鍵仍然可用。") }
    static var menuBarIconHiddenDesc: String { s("Hidden. Open 预翻译 for Mac again to come back here.", ko: "숨김 상태 · 预翻译 for Mac를 다시 열면 이 창이 열립니다.", zh: "图标已隐藏，再次打开 预翻译 for Mac 可返回此处。", tw: "圖示已隱藏，再次開啟 预翻译 for Mac 可返回此處。") }
    static var menuBarIconMissing: String { s("Icon not showing? Open Menu Bar Settings…", ko: "아이콘이 안 보이나요? 메뉴 막대 설정 열기…", zh: "找不到图标？打开菜单栏设置…", tw: "找不到圖示？開啟選單列設定…") }
    static var showHitRateInMenuBar: String { s("Show Hit Rate in Menu Bar", ko: "메뉴바에 적중률 표시", zh: "在菜单栏显示命中率", tw: "在選單列顯示命中率") }
    static var showHitRateInMenuBarDesc: String { s("While live translating, show how many lines the pre-translation database matched.", ko: "실시간 번역 중 사전 번역 적중률을 아이콘 옆에 표시합니다.", zh: "实时翻译时，在图标旁显示预翻译库命中了多少句。", tw: "即時翻譯時，在圖示旁顯示預翻譯庫命中了多少句。") }
    static var hitRateLowWarning: String { s("Low hit rate. You may have picked the wrong database.", ko: "적중률이 낮습니다. 데이터베이스를 잘못 골랐을 수 있습니다.", zh: "命中率低，可能选错了库", tw: "命中率低，可能選錯了庫") }
    // MARK: - 预翻译库（导入制）

    static var lunaLibrarySection: String { s("Pre-translation Databases", ko: "Pre-translation Databases", zh: "预翻译库 · 实时字幕", tw: "預翻譯庫 · 即時字幕") }
    static var lunaUseToggle: String { s("Use Luna pre-translation database (no machine translation)", ko: "Use Luna pre-translation database (no machine translation)", zh: "使用 Luna 预翻译库（不用机器翻译）", tw: "使用 Luna 預翻譯庫（不用機器翻譯）") }
    static var lunaLibraryEmpty: String { s("No database imported yet", ko: "No database imported yet", zh: "还没有导入预翻译库", tw: "還沒有匯入預翻譯庫") }
    static var lunaLibraryImport: String { s("Import .sqlite…", ko: "Import .sqlite…", zh: "导入 .sqlite…", tw: "匯入 .sqlite…") }
    static var lunaLibraryImportPanel: String { s("Choose a LunaTranslator pre-translation SQLite database", ko: "Choose a LunaTranslator pre-translation SQLite database", zh: "选择 LunaTranslator 的预翻译 SQLite 数据库", tw: "選擇 LunaTranslator 的預翻譯 SQLite 資料庫") }
    static var lunaLibraryRemove: String { s("Remove", ko: "Remove", zh: "删除", tw: "刪除") }
    static var lunaLibraryUse: String { s("Use this database", ko: "Use this database", zh: "使用这个库", tw: "使用這個庫") }
    static func lunaLibraryLimitNote(_ n: Int) -> String { s("Up to \(n) databases for now. Remove one to import another.", ko: "Up to \(n) databases for now. Remove one to import another.", zh: "目前支持 \(n) 个库。要导入新的，先删掉一个。", tw: "目前支援 \(n) 個庫。要匯入新的，先刪掉一個。") }
    static var lunaLibraryHelp: String { s("Importing copies the file into the app, so you can move or delete the original. Removing only deletes the app's copy. Used by live translation only; unmatched lines show the original text instead of falling back to machine translation.", ko: "Importing copies the file into the app, so you can move or delete the original. Removing only deletes the app's copy. Used by live translation only; unmatched lines show the original text instead of falling back to machine translation.", zh: "导入时会复制一份到 App 里，原文件之后可以移走或删除；删除只删 App 里的这份。只作用于实时翻译，没匹配上的句子显示原文，不会偷偷改用机器翻译。", tw: "匯入時會複製一份到 App 裡，原檔案之後可以移走或刪除；刪除只刪 App 裡的這份。只作用於即時翻譯，沒匹配上的句子顯示原文，不會偷偷改用機器翻譯。") }
    static var lunaLookAlikeToggle: String { s("Tolerate look-alike characters", ko: "비슷한 글자 오인식 허용", zh: "形近字容错", tw: "形近字容錯") }
    static var lunaLookAlikeDesc: String { s("When OCR misreads one character as a look-alike (仁/化, っ/つ, ー/一…), swap it back and look again; a line of 10+ characters with a single wrong, missing or extra character is also matched when no other line is close. Helps short lines most. There is a very small chance of showing a different line's translation. Applies the next time live translation starts.", ko: "OCR이 한 글자를 비슷한 글자로 잘못 읽었을 때(仁/化, っ/つ, ー/一…) 바꿔서 다시 찾습니다. 10자 이상인 대사에서 한 글자만 틀리거나 빠진 경우에도, 비슷한 다른 대사가 없으면 맞춥니다. 짧은 대사에 특히 도움이 됩니다. 아주 드물게 다른 대사의 번역이 나올 수 있습니다. 다음에 실시간 번역을 시작할 때부터 적용됩니다.", zh: "识别把一个字认成形近字（仁/化、っ/つ、ー/一……）时，换回来再查库；10 个字以上的句子只错、漏或多了一个字，而且库里没有别的相近句子时，也会配上。对短句帮助最大。有极小概率配到另一句的译文。下次开始实时翻译时生效。", tw: "辨識把一個字認成形近字（仁/化、っ/つ、ー/一……）時，換回來再查庫；10 個字以上的句子只錯、漏或多了一個字，而且庫裡沒有別的相近句子時，也會配上。對短句幫助最大。有極小機率配到另一句的譯文。下次開始即時翻譯時生效。") }
    static var lunaLibraryRemoveTitle: String { s("Remove this database?", ko: "Remove this database?", zh: "删除这个预翻译库？", tw: "刪除這個預翻譯庫？") }
    static func lunaLibraryRemoveMessage(_ name: String) -> String { s("“\(name)” will be removed from the app. Your original file is not affected.", ko: "“\(name)” will be removed from the app. Your original file is not affected.", zh: "将从 App 里删除「\(name)」，你原来的文件不受影响。", tw: "將從 App 裡刪除「\(name)」，你原來的檔案不受影響。") }
    static var lunaLibraryImportFailed: String { s("Couldn't import", ko: "Couldn't import", zh: "导入失败", tw: "匯入失敗") }
    static func lunaLibraryFull(_ n: Int) -> String { s("Up to \(n) databases for now. Remove one first.", ko: "Up to \(n) databases for now. Remove one first.", zh: "目前支持 \(n) 个库，请先删掉一个。", tw: "目前支援 \(n) 個庫，請先刪掉一個。") }
    static var lunaLibraryNotLuna: String { s("This file isn't a LunaTranslator pre-translation database.", ko: "This file isn't a LunaTranslator pre-translation database.", zh: "这个文件不是 LunaTranslator 的预翻译库。", tw: "這個檔案不是 LunaTranslator 的預翻譯庫。") }
    static func lunaLibraryCopyFailed(_ reason: String) -> String { s("Couldn't copy the file: \(reason)", ko: "Couldn't copy the file: \(reason)", zh: "复制文件失败：\(reason)", tw: "複製檔案失敗：\(reason)") }
    static var lunaLibraryMissing: String { s("Import a .sqlite database first in Settings → Advanced → Pre-translation Databases.", ko: "Import a .sqlite database first in Settings → Advanced → Pre-translation Databases.", zh: "请先在设置 → 高级 → 预翻译库中导入 .sqlite 文件", tw: "請先在設定 → 進階 → 預翻譯庫中匯入 .sqlite 檔案") }

    static var lunaFileMissing: String { s("Pre-translation database not found. Please import it again.", ko: "Pre-translation database not found. Please import it again.", zh: "找不到预翻译库，请重新导入", tw: "找不到預翻譯庫，請重新匯入") }
    static func lunaOpenFailed(_ message: String) -> String { s("Couldn't open SQLite: \(message)", ko: "Couldn't open SQLite: \(message)", zh: "无法打开 SQLite：\(message)", tw: "無法開啟 SQLite：\(message)") }
    static var lunaNotStandard: String { s("Not a standard Luna pre-translation database: artificialtrans/source/machineTrans missing", ko: "Not a standard Luna pre-translation database: artificialtrans/source/machineTrans missing", zh: "这不是标准 Luna 预翻译库：缺少 artificialtrans/source/machineTrans", tw: "這不是標準 Luna 預翻譯庫：缺少 artificialtrans/source/machineTrans") }
    static var lunaNoRows: String { s("The database has no usable Japanese–Chinese entries.", ko: "The database has no usable Japanese–Chinese entries.", zh: "数据库中没有可用的日中对照记录", tw: "資料庫中沒有可用的日中對照記錄") }
    // MARK: - 未命中记录与问题反馈
    static var missFolderName: String { s("Pre-translation Feedback", ko: "Pre-translation Feedback", zh: "预翻译问题反馈", tw: "預翻譯問題回報") }
    static var missRecordToggle: String { s("Save missed lines automatically", ko: "Save missed lines automatically", zh: "自动保存未命中的画面", tw: "自動儲存未命中的畫面") }
    static var missRecordDesc: String { s("When a line finds no match, the captured region and the recognized text are saved to a folder on your Desktop, named after the database. Nothing is uploaded. Each database keeps the latest 500 images.", ko: "When a line finds no match, the captured region and the recognized text are saved to a folder on your Desktop, named after the database. Nothing is uploaded. Each database keeps the latest 500 images.", zh: "有句子没命中时，把框选区域的画面和识别出的文字存到桌面的文件夹里，按库名分开放。只存在本机，不会上传；每个库保留最近 500 张。", tw: "有句子沒命中時，把框選區域的畫面和辨識出的文字存到桌面的資料夾裡，按庫名分開放。只存在本機，不會上傳；每個庫保留最近 500 張。") }
    static var missRecordMenuEnable: String { s("Save Missed Lines for Feedback", ko: "Save Missed Lines for Feedback", zh: "记录未命中的画面，方便反馈", tw: "記錄未命中的畫面，方便回報") }
    static var feedbackCopy: String { s("Copy Problem Summary", ko: "Copy Problem Summary", zh: "复制问题说明", tw: "複製問題說明") }
    static var feedbackCopied: String { s("Copied", ko: "Copied", zh: "已复制，可以直接粘贴", tw: "已複製，可以直接貼上") }
    static var feedbackOpenFolder: String { s("Open Folder", ko: "Open Folder", zh: "打开文件夹", tw: "打開資料夾") }
    static var feedbackHelp: String { s("The summary is plain text: paste it into an email or a message. Attach images from the folder if asked.", ko: "The summary is plain text: paste it into an email or a message. Attach images from the folder if asked.", zh: "问题说明是一段文字，可以直接粘贴到邮件、私信或评论里；需要图片时，把文件夹里的图一起发来。", tw: "問題說明是一段文字，可以直接貼到郵件、私訊或留言裡；需要圖片時，把資料夾裡的圖一起傳來。") }
    static var feedbackTitle: String { s("[Pre-translation for Mac: problem report]", ko: "[Pre-translation for Mac: problem report]", zh: "【预翻译 for Mac 问题反馈】", tw: "【预翻译 for Mac 問題回報】") }
    static func feedbackLibrary(_ name: String, rows: Int?) -> String {
        let count = rows.map { s(" (\($0) lines)", ko: " (\($0) lines)", zh: "（\($0) 条）", tw: "（\($0) 條）") } ?? ""
        return s("Game / database: ", ko: "Game / database: ", zh: "游戏／库：", tw: "遊戲／庫：") + name + count
    }
    static var feedbackNoLibrary: String { s("(no database selected)", ko: "(no database selected)", zh: "（没有选库）", tw: "（沒有選庫）") }
    static func feedbackVersions(app: String, system: String) -> String { s("App \(app), macOS \(system)", ko: "App \(app), macOS \(system)", zh: "App 版本：\(app)　系统：macOS \(system)", tw: "App 版本：\(app)　系統：macOS \(system)") }
    static func feedbackHitRate(percent: Int, total: Int, missed: Int) -> String { s("Hit rate this session: \(percent)% (\(total) lines, \(missed) missed)", ko: "Hit rate this session: \(percent)% (\(total) lines, \(missed) missed)", zh: "本次命中率：\(percent)%（共 \(total) 句，漏 \(missed) 句）", tw: "本次命中率：\(percent)%（共 \(total) 句，漏 \(missed) 句）") }
    static func feedbackMissHeader(shown: Int, total: Int) -> String { s("Missed lines as the app read them (latest \(shown) of \(total)):", ko: "Missed lines as the app read them (latest \(shown) of \(total)):", zh: "漏掉的句子（App 读到的字，最近 \(shown) 句，共存了 \(total) 句）：", tw: "漏掉的句子（App 讀到的字，最近 \(shown) 句，共存了 \(total) 句）：") }
    static var feedbackNoMisses: String { s("No missed lines saved yet. Turn on \"Save missed lines automatically\" and play a little.", ko: "No missed lines saved yet. Turn on \"Save missed lines automatically\" and play a little.", zh: "还没有存下未命中的句子。先打开「自动保存未命中的画面」，再玩一会儿。", tw: "還沒有存下未命中的句子。先打開「自動儲存未命中的畫面」，再玩一會兒。") }

    static func hitRateSummary(_ percent: Int) -> String { s("Hit \(percent)%", ko: "Hit \(percent)%", zh: "命中 \(percent)%", tw: "命中 \(percent)%") }
    static var aboutBasedOn: String { s("Modified from ScreenTranslate, released under GPLv3", ko: "Modified from ScreenTranslate, released under GPLv3", zh: "基于 ScreenTranslate 修改，以 GPLv3 协议发布", tw: "基於 ScreenTranslate 修改，以 GPLv3 授權發布") }
    static var aboutUpstreamLink: String { s("ScreenTranslate original project (GitHub)", ko: "ScreenTranslate original project (GitHub)", zh: "ScreenTranslate 原项目（GitHub）", tw: "ScreenTranslate 原專案（GitHub）") }

    // MARK: - 联系作者

    static var contactAuthor: String { s("Contact the Author…", ko: "Contact the Author…", zh: "联系作者…", tw: "聯絡作者…") }
    static var contactWindowTitle: String { s("Contact the Author", ko: "Contact the Author", zh: "联系作者", tw: "聯絡作者") }
    static var contactIntro: String { s("Found a problem or want a new feature? Let me know.", ko: "Found a problem or want a new feature? Let me know.", zh: "用着有问题、想要新功能，都可以告诉我。", tw: "用著有問題、想要新功能，都可以告訴我。") }
    static func contactSocialTitle(_ name: String) -> String { s("Xiaohongshu · \(name)", ko: "Xiaohongshu · \(name)", zh: "小红书 · \(name)", tw: "小紅書 · \(name)") }
    static var contactSocialDetail: String { s("Updates and replies are here first. Same name on Bilibili and Douyin.", ko: "Updates and replies are here first. Same name on Bilibili and Douyin.", zh: "主要在这里更新和回复，B站、抖音同名", tw: "主要在這裡更新和回覆，B站、抖音同名") }
    static var contactCopyName: String { s("Copy Name", ko: "Copy Name", zh: "复制名字", tw: "複製名字") }
    static func contactQuarkTitle(_ id: String) -> String { s("Quark Group · \(id)", ko: "Quark Group · \(id)", zh: "夸克群 · \(id)", tw: "夸克群 · \(id)") }
    static var contactQuarkDetail: String { s("New versions are posted here first. Join to download the installer.", ko: "New versions are posted here first. Join to download the installer.", zh: "最新版第一时间发在群里，进群自己下载安装包", tw: "最新版第一時間發在群裡，進群自己下載安裝包") }
    static var contactCopyGroupID: String { s("Copy Group ID", ko: "Copy Group ID", zh: "复制群号", tw: "複製群號") }
    static var contactGitHubTitle: String { s("GitHub · Latest Version and Source", ko: "GitHub · Latest Version and Source", zh: "GitHub · 最新版和源码", tw: "GitHub · 最新版和原始碼") }
    static var contactGitHubDetail: String { s("English site; reporting a problem needs a GitHub account", ko: "English site; reporting a problem needs a GitHub account", zh: "英文网站，国内打开可能较慢\n提交问题需要 GitHub 账号", tw: "英文網站，部分地區開啟可能較慢\n提交問題需要 GitHub 帳號") }
    static var contactDownload: String { s("Download", ko: "Download", zh: "下载", tw: "下載") }
    static var contactReportIssue: String { s("Report a Problem", ko: "Report a Problem", zh: "提交问题", tw: "回報問題") }
    static var contactEmailTitle: String { s("Email", ko: "Email", zh: "邮件", tw: "電子郵件") }
    static var contactOpen: String { s("Open", ko: "Open", zh: "打开", tw: "開啟") }
    static var contactWriteEmail: String { s("Write Email", ko: "Write Email", zh: "写邮件", tw: "寫郵件") }
    static func contactVersionHint(_ version: String) -> String { s("Please include your version (\(version)) when reporting a problem.", ko: "Please include your version (\(version)) when reporting a problem.", zh: "反馈问题时请写上版本号（\(version)），方便排查。", tw: "回報問題時請寫上版本號（\(version)），方便排查。") }

    static var hideMenuBarIconTitle: String { s("Hide the menu bar icon?", ko: "메뉴바 아이콘을 숨길까요?", zh: "隐藏菜单栏图标？", tw: "隱藏選單列圖示？") }
    static var hideMenuBarIconMessage: String { s("Your shortcuts keep working. To get back to Settings, open 预翻译 for Mac again from Finder or Spotlight.", ko: "번역 단축키는 계속 작동합니다. 설정으로 돌아오려면 Finder나 Spotlight에서 预翻译 for Mac를 다시 여세요.", zh: "翻译快捷键仍然可用。要返回设置，请从访达或聚焦搜索重新打开 预翻译 for Mac。", tw: "翻譯快捷鍵仍然可用。要返回設定，請從 Finder 或 Spotlight 重新開啟 预翻译 for Mac。") }
    static var hideMenuBarIconConfirm: String { s("Hide Icon", ko: "숨기기", zh: "隐藏图标", tw: "隱藏圖示") }
    static var openHistory: String { s("Open History…", ko: "히스토리 열기…", zh: "打开历史记录…", tw: "開啟歷史記錄…") }

    /// names는 기능 이름을 ", "로 이은 문자열 — 한 개든 여러 개든 문장이 어색하지 않게 쓴다
    static func featuresWithoutShortcut(_ names: String) -> String {
        s("Without a shortcut, \(names) can't be started once the icon is hidden.",
          ko: "\(names)에는 단축키가 없어 아이콘 없이는 실행할 수 없습니다.", zh: "\(names)尚未设置快捷键，隐藏图标后将无法启动这些功能。", tw: "\(names)尚未設定快捷鍵，隱藏圖示後將無法啟動這些功能。")
    }

    // MARK: - API Keys

    static var apiKeysSection: String { s("API Keys", ko: "API 키", zh: "API 密钥", tw: "API 金鑰") }
    static var enterApiKey: String { s("Enter API Key", ko: "API 키 입력", zh: "输入 API 密钥", tw: "輸入 API 金鑰") }
    static var apiKeyRequired: String { s("API key required to use this engine.", ko: "이 엔진을 사용하려면 API 키가 필요합니다.", zh: "使用此引擎需要 API 密钥。", tw: "使用此引擎需要 API 金鑰。") }
    static var apiKeySaved: String { s("Saved", ko: "저장됨", zh: "已保存", tw: "已儲存") }
    static var clear: String { s("Clear", ko: "삭제", zh: "清除", tw: "清除") }
    static var apiKeyInvalid: String { s("API key is invalid. Please check your key.", ko: "API 키가 유효하지 않습니다. 키를 확인해주세요.", zh: "API 密钥无效，请检查后重试。", tw: "API 金鑰無效，請檢查後重試。") }
    static var quotaExceeded: String { s("API quota exceeded. Please check your plan.", ko: "API 사용량을 초과했습니다. 요금제를 확인해주세요.", zh: "API 用量已超出额度，请检查服务套餐。", tw: "API 用量已超出額度，請檢查服務方案。") }
    static var networkUnavailable: String { s("No internet connection. Check your network and try again.", ko: "인터넷에 연결되어 있지 않습니다. 네트워크를 확인한 뒤 다시 시도해주세요.", zh: "未连接互联网，请检查网络后重试。", tw: "未連線網際網路，請檢查網路後重試。") }
    static var networkTimedOut: String { s("The server took too long to respond. Please try again.", ko: "서버 응답이 너무 오래 걸립니다. 다시 시도해주세요.", zh: "服务器响应超时，请重试。", tw: "伺服器回應逾時，請重試。") }
    static var serverUnreachable: String { s("Couldn't reach the translation server.", ko: "번역 서버에 연결할 수 없습니다.", zh: "无法连接翻译服务器。", tw: "無法連線翻譯伺服器。") }
    static var invalidServerResponse: String { s("The translation server returned an unexpected response.", ko: "번역 서버가 예상하지 못한 응답을 보냈습니다.", zh: "翻译服务器返回了异常响应。", tw: "翻譯伺服器傳回了異常回應。") }
    static var regionLabel: String { s("Region", ko: "리전", zh: "服务区域", tw: "服務區域") }
    static var regionPlaceholder: String { s("e.g. koreacentral", ko: "예: koreacentral", zh: "例如：koreacentral", tw: "例如：koreacentral") }
    static var engineGuide: String { s("Engine setup guide", ko: "엔진 설정 가이드", zh: "引擎配置指南", tw: "引擎設定指南") }

    // MARK: - Engine Descriptions

    static var engineDescApple: String { s("On-device · No internet required · 20 languages · Free", ko: "온디바이스 · 인터넷 불필요 · 20개 언어 · 무료", zh: "本地运行 · 无需联网 · 支持 20 种语言 · 免费", tw: "本地執行 · 無需聯網 · 支援 20 種語言 · 免費") }
    static var engineDescDeepL: String { s("Cloud · API key required", ko: "클라우드 · API 키 필요", zh: "云端服务 · 需要 API 密钥", tw: "雲端服務 · 需要 API 金鑰") }
    static var engineDescGoogle: String { s("Cloud · API key required", ko: "클라우드 · API 키 필요", zh: "云端服务 · 需要 API 密钥", tw: "雲端服務 · 需要 API 金鑰") }
    static var engineDescAzure: String { s("Cloud · API key + region required", ko: "클라우드 · API 키 + 리전 필요", zh: "云端服务 · 需要 API 密钥和服务区域", tw: "雲端服務 · 需要 API 金鑰和服務區域") }

    // MARK: - Help Tooltips

    static var appLanguageHelp: String { s("Change the display language of the app interface", ko: "앱 인터페이스의 표시 언어를 변경합니다", zh: "更改应用界面的显示语言", tw: "更改 App 介面的顯示語言") }
    static var launchAtLoginHelp: String { s("Automatically start 预翻译 for Mac when you log in", ko: "로그인 시 预翻译 for Mac를 자동으로 시작합니다", zh: "登录电脑时自动启动 预翻译 for Mac", tw: "登入電腦時自動啟動 预翻译 for Mac") }
    static var sourceLanguageHelp: String { s("Language of the text to translate. Auto Detect works for most cases", ko: "번역할 텍스트의 언어. 대부분의 경우 자동 감지로 충분합니다", zh: "要翻译的文字所使用的语言，通常可以选择自动识别", tw: "要翻譯的文字所使用的語言，通常可以選擇自動識別") }
    static var targetLanguageHelp: String { s("Language to translate into", ko: "번역 결과 언어", zh: "翻译结果所使用的语言", tw: "翻譯結果所使用的語言") }
    static var ocrEngineHelp: String { s("Text recognition engine. Apple Vision runs on-device", ko: "텍스트 인식 엔진. Apple Vision은 온디바이스로 동작합니다", zh: "文字识别引擎，Apple Vision 在本机运行", tw: "文字識別引擎，Apple Vision 在本機執行") }
    static var shortcutHelp: String { s("Global shortcut to start screen translation. Default: Cmd+E", ko: "화면 번역을 시작하는 전역 단축키. 기본값: ⌘E", zh: "启动截图翻译的全局快捷键，默认为 ⌘E", tw: "啟動截圖翻譯的全域快捷鍵，預設為 ⌘E") }

    // MARK: - About Links

    static var aboutWebsite: String { s("Website", ko: "웹사이트", zh: "官方网站", tw: "官方網站") }
    static func aboutVersion(_ version: String) -> String { s("Version \(version)", ko: "버전 \(version)", zh: "版本 \(version) 测试版", tw: "版本 \(version) 測試版") }
    static var aboutCopyright: String { s("\u{00A9} 2026 hanchangmin (original ScreenTranslate author)\nModifications \u{00A9} 2026 TomoMakes", ko: "\u{00A9} 2026 hanchangmin (ScreenTranslate 원작자)\n수정 부분 \u{00A9} 2026 TomoMakes", zh: "© 2026 hanchangmin（ScreenTranslate 原作者）\n修改部分 © 2026 TomoMakes", tw: "© 2026 hanchangmin（ScreenTranslate 原作者）\n修改部分 © 2026 TomoMakes") }
    static var statusInstalled: String { s("Installed", ko: "설치됨", zh: "已安装", tw: "已安裝") }
    static var statusDownloadable: String { s("Not installed. Available to download", ko: "미설치, 다운로드 가능", zh: "未安装，可下载", tw: "未安裝，可下載") }
    static var statusUnsupported: String { s("Not supported", ko: "지원되지 않음", zh: "不支持", tw: "不支援") }
    static var engineReady: String { s("Ready to use", ko: "사용 가능", zh: "可以使用", tw: "可以使用") }
    static var engineNeedsKey: String { s("API key required", ko: "API 키 필요", zh: "需要 API 密钥", tw: "需要 API 金鑰") }
    static var historySucceeded: String { s("Translation succeeded", ko: "번역 성공", zh: "翻译成功", tw: "翻譯成功") }
    static var historyFailed: String { s("Translation failed", ko: "번역 실패", zh: "翻译失败", tw: "翻譯失敗") }
    static var aboutEnginesGuide: String { s("Translation Engines Guide", ko: "번역 엔진 가이드", zh: "翻译引擎指南", tw: "翻譯引擎指南") }
    static var aboutPrivacyPolicy: String { s("Privacy Policy", ko: "개인정보처리방침", zh: "隐私政策", tw: "隱私政策") }

    // MARK: - Advanced

    static var autoCopyToClipboard: String { s("Auto-copy to Clipboard", ko: "자동 클립보드 복사", zh: "自动复制译文", tw: "自動複製譯文") }
    static var autoCopyToClipboardDesc: String { s("Automatically copy translated text to clipboard.", ko: "번역 완료 시 번역문을 자동으로 클립보드에 복사합니다.", zh: "翻译完成后，自动将译文复制到剪贴板。", tw: "翻譯完成後，自動將譯文複製到剪貼簿。") }

    static var popupFontSize: String { s("Popup Font Size", ko: "팝업 글자 크기", zh: "字幕字号", tw: "字幕字號") }
    static var popupFontSizeDesc: String { s("Adjust the text size of translation popup.", ko: "번역 팝업의 글자 크기를 조절합니다.", zh: "调整实时字幕的文字大小。", tw: "調整即時字幕的文字大小。") }

    // MARK: - Font Settings

    static var popupFont: String { s("Popup Font", ko: "팝업 폰트", zh: "弹窗字体", tw: "彈窗字型") }
    static var popupFontDesc: String { s("Change the font of translation popup text.", ko: "번역 팝업의 텍스트 폰트를 변경합니다.", zh: "更改翻译弹窗使用的字体。", tw: "更改翻譯彈窗使用的字型。") }
    static var systemDefault: String { s("System Default", ko: "시스템 기본", zh: "系统默认", tw: "系統預設") }
    static var addFont: String { s("Add Font...", ko: "폰트 추가...", zh: "添加字体…", tw: "新增字型…") }
    static var fontPreview: String { s("Font Preview", ko: "폰트 미리보기", zh: "字体预览", tw: "字型預覽") }
    static var removeFont: String { s("Remove Font", ko: "폰트 삭제", zh: "移除字体", tw: "移除字型") }
    static func removeFontConfirmation(name: String) -> String { s("Are you sure you want to remove '\(name)'?", ko: "'\(name)' 폰트를 삭제하시겠습니까?", zh: "确定移除字体“\(name)”吗？", tw: "確定移除字型「\(name)」嗎？") }
    static var fontImportFailed: String { s("Failed to import font.", ko: "폰트 가져오기에 실패했습니다.", zh: "字体导入失败。", tw: "字型匯入失敗。") }
    static var fontDownloadFailed: String { s("Failed to download font.", ko: "폰트 다운로드에 실패했습니다.", zh: "字体下载失败。", tw: "字型下載失敗。") }
    static var fontSelectMessage: String { s("Select a .ttf or .otf font file to use in translation popups.", ko: "번역 팝업에 사용할 .ttf 또는 .otf 폰트 파일을 선택하세요.", zh: "选择用于翻译弹窗的 .ttf 或 .otf 字体文件。", tw: "選擇用於翻譯彈窗的 .ttf 或 .otf 字型檔案。") }
    static var fontDownloadConfirmTitle: String { s("Download Font", ko: "폰트 다운로드", zh: "下载字体", tw: "下載字型") }
    static func fontDownloadConfirmMessage(name: String, size: String) -> String {
        s("Download \(name) (\(size))?", ko: "\(name) (\(size))을 다운로드할까요?", zh: "下载 \(name)（\(size)）吗？", tw: "下載 \(name)（\(size)）嗎？")
    }

    /// 타겟 언어별 폰트 미리보기 샘플 텍스트
    static func fontPreviewSample(for languageCode: String) -> String {
        switch languageCode {
        case "ko": return "번역된 텍스트가 이렇게 표시됩니다."
        case "en": return "The quick brown fox jumps over the lazy dog."
        case "ja": return "翻訳されたテキストはこのように表示されます。"
        case "zh-Hans": return "翻译后的文本将以这种方式显示。"
        case "zh-Hant": return "翻譯後的文字將以這種方式顯示。"
        case "fr": return "Le texte traduit s'affichera de cette façon."
        case "de": return "Der übersetzte Text wird so angezeigt."
        case "es": return "El texto traducido se mostrará de esta manera."
        case "it": return "Il testo tradotto verrà visualizzato in questo modo."
        case "pt": return "O texto traduzido será exibido desta forma."
        case "ru": return "Переведённый текст будет отображаться так."
        case "ar": return "سيتم عرض النص المترجم بهذه الطريقة."
        case "nl": return "De vertaalde tekst wordt op deze manier weergegeven."
        case "hi": return "अनुवादित पाठ इस तरह प्रदर्शित होगा।"
        case "id": return "Teks terjemahan akan ditampilkan seperti ini."
        case "pl": return "Przetłumaczony tekst będzie wyświetlany w ten sposób."
        case "th": return "ข้อความที่แปลแล้วจะแสดงในลักษณะนี้"
        case "tr": return "Çevrilen metin bu şekilde görüntülenecektir."
        case "uk": return "Перекладений текст буде відображатися так."
        case "vi": return "Văn bản dịch sẽ được hiển thị như thế này."
        default: return "The quick brown fox jumps over the lazy dog."
        }
    }

    static var matchPopupWidth: String { s("Fit Popup to Selection", ko: "팝업 너비 맞춤", zh: "弹窗宽度跟随选区", tw: "彈窗寬度跟隨選區") }
    static var matchPopupWidthDesc: String { s("Matches popup width to captured area when enabled.", ko: "활성화 시 캡처 영역에 팝업 너비를 맞춥니다.", zh: "开启后，翻译弹窗的宽度与截图选区一致。", tw: "開啟後，翻譯彈窗的寬度與截圖選區一致。") }
    static var matchPopupWidthHelp: String { s("Match the translation popup width to the captured selection area.", ko: "번역 팝업의 너비를 캡처한 선택 영역에 맞춥니다.", zh: "让翻译弹窗宽度与框选区域一致。", tw: "讓翻譯彈窗寬度與框選區域一致。") }

    static var advancedSection: String { s("Advanced", ko: "고급", zh: "高级", tw: "進階") }
    static var ocrTextPreprocessing: String { s("Text Preprocessing", ko: "텍스트 전처리", zh: "识别文字整理", tw: "識別文字整理") }
    static var ocrTextPreprocessingDesc: String { s("Merge line breaks from OCR into natural sentences before translation.", ko: "번역 전 OCR 줄바꿈을 자연스러운 문장으로 병합합니다.", zh: "翻译前将识别结果中的换行合并为完整句子。", tw: "翻譯前將識別結果中的換行合併為完整句子。") }

    static func languagePackMessage(name: String) -> String {
        s("\(name) language pack is not installed.\nWould you like to download it now?",
          ko: "\(name) 언어팩이 설치되지 않았습니다.\n지금 다운로드할까요?", zh: "尚未安装\(name)语言包。\n现在下载吗？", tw: "尚未安裝\(name)語言包。\n現在下載嗎？")
    }

    // MARK: - History

    static var translationHistory: String { s("Translation History", ko: "번역 히스토리", zh: "翻译历史", tw: "翻譯歷史") }
    static var deleteAll: String { s("Delete All", ko: "전체 삭제", zh: "全部删除", tw: "全部刪除") }
    static var copyTranslation: String { s("Copy Translation", ko: "번역문 복사", zh: "复制译文", tw: "複製譯文") }
    static var copyOriginal: String { s("Copy Original", ko: "원문 복사", zh: "复制原文", tw: "複製原文") }
    static var delete: String { s("Delete", ko: "삭제", zh: "删除", tw: "刪除") }
    static var deleteAllHistory: String { s("Delete All History", ko: "모든 히스토리 삭제", zh: "删除全部历史记录", tw: "刪除全部歷史記錄") }
    static var cancel: String { s("Cancel", ko: "취소", zh: "取消", tw: "取消") }
    static var deleteAllConfirmation: String {
        s("All translation history will be deleted.\nThis action cannot be undone.",
          ko: "모든 번역 히스토리가 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.", zh: "将删除全部翻译历史记录。\n此操作无法撤销。", tw: "將刪除全部翻譯歷史記錄。\n此操作無法復原。")
    }
    static var noHistoryMessage: String { s("No translation history", ko: "번역 히스토리가 없습니다", zh: "暂无翻译记录", tw: "暫無翻譯記錄") }
    static var translatedText: String { s("Translation", ko: "번역문", zh: "译文", tw: "譯文") }
    static var selectRecord: String { s("Select a translation record", ko: "번역 기록을 선택하세요", zh: "请选择一条翻译记录", tw: "請選擇一條翻譯記錄") }

    // MARK: - Permission

    static var permissionRequired: String { s("Screen access permission required", ko: "화면 접근 권한이 필요합니다", zh: "需要屏幕录制权限", tw: "需要螢幕錄製權限") }
    static var permissionDescription: String {
        s("Please allow 预翻译 for Mac in System Settings > Privacy & Security > Screen Recording.",
          ko: "시스템 설정 > 개인 정보 보호 및 보안 > 화면 기록에서 预翻译 for Mac를 허용해주세요.", zh: "请前往“系统设置 → 隐私与安全性 → 屏幕录制”，允许 预翻译 for Mac 访问屏幕。", tw: "請前往「系統設定 → 隱私與安全性 → 螢幕錄製」，允許 预翻译 for Mac 存取螢幕。")
    }
    static var openSystemSettings: String { s("Open System Settings", ko: "시스템 설정 열기", zh: "打开系统设置", tw: "開啟系統設定") }

    // MARK: - Onboarding

    static var onboardingWelcome: String { s("Welcome to 预翻译 for Mac", ko: "预翻译 for Mac에 오신 것을 환영합니다", zh: "欢迎使用 预翻译 for Mac", tw: "歡迎使用 预翻译 for Mac") }
    static var onboardingShortcutTitle: String { s("Set Your Shortcut", ko: "단축키를 설정하세요", zh: "设置快捷键", tw: "設定快捷鍵") }
    static var onboardingShortcutDesc: String { s("Press the shortcut anywhere to translate text on screen.", ko: "어디서든 단축키를 눌러 화면의 텍스트를 번역하세요.", zh: "在任何界面按下快捷键，即可翻译屏幕上的文字。", tw: "在任何介面按下快捷鍵，即可翻譯螢幕上的文字。") }
    static var onboardingFlow1: String { s("Press shortcut", ko: "단축키 누르기", zh: "按下快捷键", tw: "按下快捷鍵") }
    static var onboardingFlow2: String { s("Select area", ko: "영역 선택", zh: "框选区域", tw: "框選區域") }
    static var onboardingFlow3: String { s("See translation", ko: "번역 확인", zh: "查看译文", tw: "檢視譯文") }
    static var onboardingChangeHint: String { s("Use the default or click to change", ko: "기본값을 사용하거나 클릭하여 변경하세요", zh: "使用默认快捷键，或点击修改", tw: "使用預設快捷鍵，或點選修改") }
    static var onboardingLangTitle: String { s("Download Language Pack", ko: "언어팩 다운로드", zh: "下载语言包", tw: "下載語言包") }
    static var onboardingLangAutoSet: String { s("Your translation language has been set automatically.", ko: "번역 언어가 자동으로 설정되었습니다.", zh: "已自动设置译文语言。", tw: "已自動設定譯文語言。") }
    static var onboardingLangChoose: String { s("Which language do you want to translate into?", ko: "어떤 언어로 번역할까요?", zh: "你想翻译成哪种语言？", tw: "你想翻譯成哪種語言？") }
    static var onboardingLangInstalled: String { s("Language pack installed", ko: "언어팩 설치됨", zh: "已安装语言包", tw: "已安裝語言包") }
    static var onboardingLangNotInstalled: String { s("Language pack not installed", ko: "언어팩 미설치", zh: "未安装语言包", tw: "未安裝語言包") }
    static var onboardingNext: String { s("Next", ko: "다음", zh: "下一步", tw: "下一步") }
    static var onboardingDone: String { s("Get Started", ko: "시작하기", zh: "开始使用", tw: "開始使用") }
    // Onboarding Permission Step
    static var onboardingPermDesc: String {
        s("预翻译 for Mac needs screen recording permission to read text on your screen.",
          ko: "화면의 텍스트를 읽기 위해 화면 기록 권한이 필요합니다.", zh: "预翻译 for Mac 需要屏幕录制权限，以识别屏幕上的文字。", tw: "预翻译 for Mac 需要螢幕錄製權限，以識別螢幕上的文字。")
    }
    static var onboardingPermPrivacy1: String {
        s("Used only for text recognition",
          ko: "텍스트 인식에만 사용", zh: "屏幕画面仅用于文字识别", tw: "螢幕畫面僅用於文字識別")
    }
    static var onboardingPermPrivacy2: String {
        s("No recording, saving, or sending",
          ko: "녹화·저장·전송 없음", zh: "不会录制、保存或发送屏幕画面", tw: "不會錄製、儲存或傳送螢幕畫面")
    }
    static var onboardingPermPrivacy3: String {
        s("All processing stays on your device",
          ko: "모든 처리는 기기 내에서 수행", zh: "文字识别在本机完成", tw: "文字識別在本機完成")
    }
    static var onboardingPermRestart: String {
        s("The app will restart automatically after granting permission.",
          ko: "권한 허용 후 앱이 자동으로 다시 시작됩니다.", zh: "授权后，应用将自动重新启动。", tw: "授權後，App 將自動重新啟動。")
    }
    static var onboardingDownloadLater: String {
        s("Download Later",
          ko: "나중에 다운로드", zh: "稍后下载", tw: "稍後下載")
    }

    // MARK: - Timestamp

    static var justNow: String { s("Just now", ko: "방금 전", zh: "刚刚", tw: "剛剛") }
    static func minutesAgo(_ n: Int) -> String { s("\(n) min ago", ko: "\(n)분 전", zh: "\(n) 分钟前", tw: "\(n) 分鐘前") }
    static var today: String { s("Today", ko: "오늘", zh: "今天", tw: "今天") }
    static var yesterday: String { s("Yesterday", ko: "어제", zh: "昨天", tw: "昨天") }

    /// 스마트 타임스탬프: 최근은 상대 시간, 오래된 건 절대 시간.
    static func smartTimestamp(for date: Date) -> String {
        let now = Date()
        let seconds = now.timeIntervalSince(date)
        let calendar = Calendar.current

        if seconds < 60 {
            return justNow
        }
        if seconds < 3600 {
            return minutesAgo(Int(seconds / 60))
        }

        let timeString = shortTimeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "\(today) \(timeString)"
        }
        if calendar.isDateInYesterday(date) {
            return "\(yesterday) \(timeString)"
        }

        return "\(monthDayFormatter.string(from: date)) \(timeString)"
    }

    /// 호출마다 DateFormatter를 만들면 히스토리 50행 스크롤 시 수백 개가 생성된다. 캐시한다.
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// "M/d" 고정 포맷은 일/월 순서를 쓰는 로케일에서 뒤집혀 읽힌다. 템플릿으로 로케일에 맞춘다.
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    // MARK: - Drag Translation (Beta)

    static var dragTranslate: String { s("Drag Translate", ko: "드래그 번역", zh: "划词翻译", tw: "劃詞翻譯") }
    static var dragTranslateShortcut: String { s("Drag Translation Shortcut", ko: "드래그 번역 단축키", zh: "划词翻译快捷键", tw: "劃詞翻譯快捷鍵") }
    static var dragTranslateShortcutHelp: String { s("Global shortcut to translate selected text. Select text in any app, then press the shortcut.", ko: "선택한 텍스트를 번역하는 전역 단축키. 아무 앱에서 텍스트를 선택한 후 단축키를 누르세요.", zh: "在任意应用中选中文字，再按下此全局快捷键进行翻译。", tw: "在任何 App 中選取文字，再按下此全域快捷鍵進行翻譯。") }
    static var noSelectedText: String { s("No text selected. Please select text first.", ko: "선택된 텍스트가 없습니다. 먼저 텍스트를 선택해주세요.", zh: "尚未选中文字，请先选择要翻译的文字。", tw: "尚未選取文字，請先選擇要翻譯的文字。") }
    static var accessibilityPermissionRequired: String { s("Accessibility permission required", ko: "손쉬운 사용 권한이 필요합니다", zh: "需要辅助功能权限", tw: "需要輔助功能權限") }
    static var accessibilityPermissionDescription: String {
        s("Please allow 预翻译 for Mac in System Settings > Privacy & Security > Accessibility.",
          ko: "시스템 설정 > 개인 정보 보호 및 보안 > 손쉬운 사용에서 预翻译 for Mac를 허용해주세요.", zh: "请前往“系统设置 → 隐私与安全性 → 辅助功能”，允许 预翻译 for Mac 访问。", tw: "請前往「系統設定 → 隱私與安全性 → 輔助功能」，允許 预翻译 for Mac 存取。")
    }
    static var betaFeature: String { s("Beta", ko: "베타", zh: "测试版", tw: "測試版") }

    // MARK: - Errors

    static func liveLanguagePackMissing(_ names: String) -> String {
        s("Live Translate uses Apple Translation. Download the \(names) language pack in Settings first.",
          ko: "실시간 번역은 Apple 번역을 씁니다. 설정에서 \(names) 언어팩을 먼저 받아 주세요.", zh: "Apple 实时翻译需要语言包，请先在设置中下载\(names)语言包。", tw: "Apple 即時翻譯需要語言包，請先在設定中下載\(names)語言包。")
    }

    static func liveTranslateStopped(_ reason: String) -> String {
        s("Live Translate stopped: \(reason)", ko: "실시간 번역이 멈췄습니다: \(reason)", zh: "实时翻译已停止：\(reason)", tw: "即時翻譯已停止：\(reason)")
    }

    static var noTextFound: String { s("No text found in the selected area.", ko: "선택한 영역에서 텍스트를 찾을 수 없습니다.", zh: "未在框选区域内找到文字。", tw: "未在框選區域內找到文字。") }
    static var unsupportedLanguagePair: String { s("This language pair is not supported.", ko: "이 언어 조합은 지원되지 않습니다.", zh: "不支持这组翻译语言。", tw: "不支援這組翻譯語言。") }
    static var noTextToTranslate: String { s("No text to translate.", ko: "번역할 텍스트가 없습니다.", zh: "没有可翻译的文字。", tw: "沒有可翻譯的文字。") }
    static var noDisplayFound: String { s("No display found.", ko: "디스플레이를 찾을 수 없습니다.", zh: "未找到显示器。", tw: "找不到顯示器。") }
    static var cropFailed: String { s("Image crop failed.", ko: "이미지 크롭에 실패했습니다.", zh: "图像裁剪失败。", tw: "影像裁剪失敗。") }

    static func captureError(_ description: String) -> String {
        s("Capture error: \(description)", ko: "캡처 오류: \(description)", zh: "截图失败：\(description)", tw: "截圖失敗：\(description)")
    }

    static func ocrFailed(_ reason: String) -> String {
        s("Text recognition failed: \(reason)", ko: "텍스트 인식 실패: \(reason)", zh: "文字识别失败：\(reason)", tw: "文字識別失敗：\(reason)")
    }

    static func translationFailed(_ reason: String) -> String {
        s("Translation failed: \(reason)", ko: "번역 실패: \(reason)", zh: "翻译失败：\(reason)", tw: "翻譯失敗：\(reason)")
    }

    /// 클라우드 엔진이 예상 밖의 HTTP 상태를 반환했을 때의 폴백 문구.
    static func engineHttpError(_ engine: String, status: Int) -> String {
        s("The \(engine) server returned HTTP \(status).",
          ko: "\(engine) 서버가 HTTP \(status) 오류를 반환했습니다.", zh: "\(engine) 服务器返回 HTTP \(status)。", tw: "\(engine) 伺服器傳回 HTTP \(status)。")
    }

    static var invalidRequest: String {
        s("Invalid request. Check the language pair.",
          ko: "잘못된 요청입니다. 언어 조합을 확인해주세요.", zh: "请求无效，请检查原文和译文语言设置。", tw: "請求無效，請檢查原文和譯文語言設定。")
    }

    static var autoDetectFailedMessage: String {
        s("Could not detect the source language.\nFor short text, try setting the source language in Settings.",
          ko: "원문 언어를 감지하지 못했습니다.\n짧은 텍스트의 경우, 설정에서 원문 언어를 지정해 보세요.", zh: "无法识别原文语言。\n文字较短时，请尝试在设置中指定原文语言。", tw: "無法識別原文語言。\n文字較短時，請嘗試在設定中指定原文語言。")
    }

    static var openSettings: String { s("Open Settings", ko: "설정 열기", zh: "打开设置", tw: "開啟設定") }
}
