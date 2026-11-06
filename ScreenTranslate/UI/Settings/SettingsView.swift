import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import TelemetryDeck
import Translation
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var packManager = LanguagePackManager()
    @State private var fontManager = FontManager.shared
    @State private var showDownloadAlert = false
    @State private var pendingDownloadCode: String?
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var isDownloading = false
    @State private var downloadStartTime: Date?
    @State private var showRemoveFontAlert = false
    @State private var fontToRemove: String?
    @State private var downloadingFontIDs: Set<String> = []
    @State private var showFontError = false
    @State private var fontErrorMessage = ""
    @State private var showAPIKeyError = false
    @State private var previousFontName = "system"
    @State private var isDownloadingFont = false
    @State private var showFontDownloadConfirm = false
    @State private var pendingCatalogFont: FontManager.CatalogFont?

    // API Key 입력 상태
    @State private var azureRegionInput = ""

    /// @AppStorage로 직접 관찰 — 시스템이 아이콘을 빼서 값이 바뀌어도 토글이 따라온다
    @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true
    @State private var showHideIconConfirm = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L10n.generalTab, systemImage: "gearshape") }
            advancedTab
                .tabItem { Label(L10n.advancedTab, systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await packManager.refreshAllStatuses()
            // 키가 없는 BYOK 엔진이 선택되어 있으면 Apple로 되돌린다
            let selected = settings.translationProviderName
            if !settings.canUse(selected) {
                settings.translationProviderName = .apple
                AppOrchestrator.shared.updateTranslationProvider()
            }
        }
        .alert(L10n.languagePackNotInstalled, isPresented: $showDownloadAlert) {
            Button(L10n.download) {
                isDownloading = true
                downloadStartTime = Date()
                Task {
                    let downloadCode = pendingDownloadCode ?? settings.targetLanguageCode
                    let installedRef = packManager.findInstalledLanguage(excluding: downloadCode) ?? "en"

                    let source: Locale.Language
                    let target: Locale.Language
                    if downloadCode == settings.sourceLanguageCode {
                        source = Locale.Language(identifier: downloadCode)
                        target = Locale.Language(identifier: installedRef)
                    } else {
                        source = Locale.Language(identifier: installedRef)
                        target = Locale.Language(identifier: downloadCode)
                    }

                    do {
                        _ = try await TranslationBridge.shared.translate(
                            text: " ", from: source, to: target
                        )
                    } catch {
                        // 다운로드 프롬프트 표시 후 실패해도 상태 갱신
                    }
                    await packManager.refreshAllStatuses()
                    isDownloading = false
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.later, role: .cancel) {}
        } message: {
            if let code = pendingDownloadCode,
               let name = AppSettings.supportedLanguages.first(where: { $0.code == code })?.name {
                Text(L10n.languagePackMessage(name: name))
            }
        }
        .alert(L10n.removeFont, isPresented: $showRemoveFontAlert) {
            Button(L10n.delete, role: .destructive) {
                if let id = fontToRemove {
                    fontManager.removeFont(id: id)
                    if settings.popupFontName == id {
                        settings.popupFontName = "system"
                    }
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if let id = fontToRemove,
               let font = fontManager.installedFonts.first(where: { $0.id == id }) {
                Text(L10n.removeFontConfirmation(name: font.displayName))
            }
        }
        .alert(fontErrorMessage, isPresented: $showFontError) {
            Button(L10n.confirm) {}
        }
        .alert(L10n.apiKeySaveFailed, isPresented: $showAPIKeyError) {
            Button(L10n.confirm) {}
        }
        .alert(L10n.fontDownloadConfirmTitle, isPresented: $showFontDownloadConfirm) {
            Button(L10n.download) {
                guard let catalogFont = pendingCatalogFont else { return }
                startFontDownload(catalogFont)
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.cancel, role: .cancel) {
                // 이전 폰트로 롤백
                settings.popupFontName = previousFontName
                pendingCatalogFont = nil
            }
        } message: {
            if let font = pendingCatalogFont {
                Text(L10n.fontDownloadConfirmMessage(name: font.name, size: formatBytes(font.sizeBytes)))
            }
        }
        .alert(L10n.hideMenuBarIconTitle, isPresented: $showHideIconConfirm) {
            Button(L10n.hideMenuBarIconConfirm) {
                showMenuBarIcon = false
                TelemetryDeck.signal("menuBarIconHidden")
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(hideMenuBarIconMessage)
        }
        .overlay {
            if isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 8) {
                            Text(L10n.downloading)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let start = downloadStartTime {
                                Text(DateFormatting.elapsedText(from: start))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Text(L10n.downloadingHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - 일반 탭

    private var generalTab: some View {
        Form {
            Section(L10n.translationSection) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Text(L10n.targetLanguageLabel)
                            .foregroundStyle(.secondary)
                        Picker(L10n.targetLanguageLabel, selection: $settings.targetLanguageCode) {
                            ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                Label {
                                    Text(lang.name)
                                } icon: {
                                    languageStatusIcon(for: lang.code)
                                }
                                .tag(lang.code)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: settings.targetLanguageCode) { _, newValue in
                            let status = packManager.languageStatuses[newValue]
                            if status == .available {
                                pendingDownloadCode = newValue
                                showDownloadAlert = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(L10n.targetLanguageHelp)
                }
            }

            Section(L10n.shortcutSection) {
                KeyboardShortcuts.Recorder(L10n.liveTranslateShortcut, name: .liveTranslate)
            }

            Section(L10n.appSection) {
                Picker(L10n.appLanguageLabel, selection: $settings.appLanguage) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }
                .pickerStyle(.menu)
                .help(L10n.appLanguageHelp)

                Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
                    .help(L10n.launchAtLoginHelp)
                    .onChange(of: launchAtLogin) { _, newValue in
                        Task {
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try await SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                            }
                        }
                    }

                Toggle(isOn: menuBarIconBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.showMenuBarIcon)
                        Text(showMenuBarIcon ? L10n.menuBarIconDesc : L10n.menuBarIconHiddenDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .help(L10n.showMenuBarIconHelp)

                // macOS 26부터 시스템 설정에서 앱별로 메뉴바 아이콘을 끌 수 있다.
                // 앱은 그 상태를 알 수 없으므로(메뉴바 항목 창을 제어 센터가 소유) 바로가기만 둔다.
                if #available(macOS 26, *) {
                    if showMenuBarIcon {
                        Button(L10n.menuBarIconMissing) {
                            openSystemMenuBarSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }

                // 메뉴바 메뉴에만 있던 항목 — 아이콘을 숨겨도 여기서 닿을 수 있어야 한다
                HStack {
                    Button(L10n.aboutApp) {
                        AppOrchestrator.shared.showAbout()
                    }
                    Spacer()
                    Button(L10n.quit) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    // MARK: - 고급 탭

    private var advancedTab: some View {
        Form {
            Section("Luna 预翻译 · 实时字幕") {
                Toggle("使用 Luna SQLite 译文库（不用 AI 机翻）", isOn: $settings.useLunaPretranslation)
                HStack {
                    Text(settings.lunaDatabasePath.isEmpty ? "未选择数据库" : URL(fileURLWithPath: settings.lunaDatabasePath).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择 .sqlite…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.message = "选择 LunaTranslator 的预翻译 SQLite 数据库"
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.lunaDatabasePath = url.path
                        }
                    }
                }
                Text("只作用于实时翻译（测试版）。无匹配时显示原文，不会偷偷改用机器翻译。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.popupSection) {
                Stepper(value: $settings.popupFontSize, in: 11...20, step: 1) {
                    HStack {
                        Text(L10n.popupFontSize)
                        Spacer()
                        Text("\(Int(settings.popupFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                }
                .help(L10n.popupFontSizeDesc)


            }

        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    // MARK: - Helpers

    /// 끌 때는 바로 숨기지 않고 확인창을 띄운다 — 되돌아오는 길을 알려줄 유일한 순간이다
    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarIcon },
            set: { isOn in
                if isOn {
                    showMenuBarIcon = true
                } else {
                    showHideIconConfirm = true
                }
            }
        )
    }

    /// 단축키가 비어 있는 기능이 있으면 아이콘 없이는 실행할 수 없다고 덧붙인다
    private var hideMenuBarIconMessage: String {
        let missing = MenuBarIconPolicy.featuresWithoutShortcut(
            hasScreenTranslateShortcut: KeyboardShortcuts.getShortcut(for: .translate) != nil,
            hasDragTranslateShortcut: KeyboardShortcuts.getShortcut(for: .dragTranslate) != nil,
            dragTranslateMode: settings.dragTranslateMode,
            hasQuickTranslateShortcut: KeyboardShortcuts.getShortcut(for: .quickTranslate) != nil,
            liveTranslateEnabled: settings.liveTranslateEnabled,
            hasLiveTranslateShortcut: KeyboardShortcuts.getShortcut(for: .liveTranslate) != nil
        )
        return MenuBarIconPolicy.hideConfirmationMessage(featuresWithoutShortcut: missing)
    }

    private func openSystemMenuBarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleFontSelection(oldValue: String, newValue: String) {
        // 다운로드 중이면 무시 (Picker .id() 리빌드에 의한 재트리거 방지)
        guard !isDownloadingFont else { return }

        // 이미 설치된 폰트이면 바로 적용
        if newValue == "system" || fontManager.installedFonts.contains(where: { $0.id == newValue }) {
            return
        }

        // 미설치 카탈로그 폰트 → 확인 팝업
        guard let catalogFont = fontManager.catalogFonts.first(where: { $0.id == newValue }) else {
            return
        }

        previousFontName = oldValue
        pendingCatalogFont = catalogFont
        showFontDownloadConfirm = true
    }

    private func startFontDownload(_ catalogFont: FontManager.CatalogFont) {
        isDownloadingFont = true
        downloadingFontIDs.insert(catalogFont.id)

        Task {
            do {
                try await fontManager.downloadFont(catalogFont)
            } catch {
                settings.popupFontName = previousFontName
                fontErrorMessage = L10n.fontDownloadFailed
                showFontError = true
            }
            isDownloadingFont = false
            downloadingFontIDs.remove(catalogFont.id)
            pendingCatalogFont = nil
        }
    }

    private func importFontFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.fontSelectMessage

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let countBefore = fontManager.installedFonts.count
        do {
            try fontManager.importFont(from: url)
            // Select the newly added font
            if fontManager.installedFonts.count > countBefore,
               let newFont = fontManager.installedFonts.last {
                settings.popupFontName = newFont.id
            }
        } catch {
            fontErrorMessage = L10n.fontImportFailed
            showFontError = true
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.1fMB", mb)
    }


    private func engineDescription(for engine: TranslationEngine) -> String {
        switch engine {
        case .apple: return L10n.engineDescApple
        case .deepl: return L10n.engineDescDeepL
        case .google: return L10n.engineDescGoogle
        case .azure: return L10n.engineDescAzure
        }
    }

    @ViewBuilder
    private func engineStatusIcon(ready: Bool) -> some View {
        if ready {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(L10n.engineReady)
        } else {
            Image(systemName: "key")
                .foregroundStyle(.orange)
                .accessibilityLabel(L10n.engineNeedsKey)
        }
    }

    @ViewBuilder
    private func languageStatusIcon(for code: String) -> some View {
        switch packManager.languageStatuses[code] {
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(L10n.statusInstalled)
        case .available:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.orange)
                .accessibilityLabel(L10n.statusDownloadable)
        case .unsupported:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.statusUnsupported)
        case .none:
            EmptyView()
        }
    }
}
