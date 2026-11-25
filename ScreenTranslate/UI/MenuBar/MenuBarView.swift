import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LunaMissRecorder.enabledKey) private var recordMisses = false
    @AppStorage(AppSettings.autoHideLiveBorderKey) private var autoHideLiveBorder = false
    @State private var libraryStore = LunaLibraryStore.shared
    @State private var updateChecker = UpdateChecker.shared
    @State private var hoveredID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if AppOrchestrator.shared.liveHitStats?.showsLowRateWarning == true {
                Text(L10n.hitRateLowWarning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                if !recordMisses {
                    menuRow(id: "enableMiss", title: L10n.missRecordMenuEnable) {
                        recordMisses = true
                    }
                }
                menuDivider
            }

            // 开始 / 停止实时翻译
            menuRow(
                id: "liveTranslate",
                title: AppOrchestrator.shared.isLiveTranslating ? L10n.stopLiveTranslation : L10n.liveTranslateMenu,
                shortcut: KeyboardShortcuts.getShortcut(for: .liveTranslate)?.description
            ) {
                dismiss()
                AppOrchestrator.shared.toggleLiveTranslation()
            }

            menuDivider

            // 预翻译库分组（直观切换 + 右侧蓝色 ✕ 直接删除）
            HStack {
                Text(L10n.lunaLibraryMenuSection)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(libraryStore.libraries.count)/\(LunaLibraryStore.maxCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 2)

            if libraryStore.libraries.isEmpty {
                Text(L10n.lunaLibraryEmpty)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
            } else {
                ForEach(libraryStore.libraries) { library in
                    libraryRow(library)
                }
            }

            if libraryStore.canImport {
                menuRow(id: "importLibrary", title: L10n.lunaLibraryImport) {
                    dismiss()
                    DispatchQueue.main.async {
                        AppOrchestrator.shared.importLunaLibraryFromMenu()
                    }
                }
            } else {
                Text(L10n.lunaLibraryFullMenuHint(LunaLibraryStore.maxCount))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 5)
            }

            menuDivider

            // 自动隐藏框选边框 & 设置
            menuRow(id: "autoHideBorder", title: L10n.autoHideLiveBorder, checked: autoHideLiveBorder) {
                autoHideLiveBorder.toggle()
            }

            menuRow(id: "settings", title: L10n.settingsMenu, shortcut: "⌘,") {
                dismiss()
                AppOrchestrator.shared.showSettings()
            }

            menuDivider

            if recordMisses {
                menuRow(id: "feedbackCopy", title: L10n.feedbackCopy) {
                    dismiss()
                    AppOrchestrator.shared.copyLunaFeedback()
                }
            }

            // 检查更新 / 发现新版本（蓝色 NEW 胶囊）
            updateRow

            menuRow(id: "contact", title: L10n.contactAuthor) {
                dismiss()
                AppOrchestrator.shared.showContact()
            }

            menuRow(id: "about", title: L10n.aboutApp) {
                dismiss()
                AppOrchestrator.shared.showAbout()
            }

            menuDivider

            menuRow(id: "quit", title: L10n.quit) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(6)
        .frame(width: 304)
    }

    // MARK: - Subviews

    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private func libraryRow(_ library: LunaLibraryStore.Library) -> some View {
        let isActive = libraryStore.activeID == library.id
        let rowID = "lib-\(library.id)"
        let isHovered = hoveredID == rowID

        return HStack(spacing: 6) {
            Button {
                AppOrchestrator.shared.activateLunaLibrary(library)
            } label: {
                HStack(spacing: 0) {
                    ZStack {
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(width: 18, alignment: .leading)

                    Text(library.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                confirmRemove(library)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.lunaLibraryRemove)
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.10) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .onHover { hovering in
            hoveredID = hovering ? rowID : (hoveredID == rowID ? nil : hoveredID)
        }
    }

    private var updateRow: some View {
        let rowID = "checkUpdates"
        let isHovered = hoveredID == rowID
        return Button {
            dismiss()
            updateChecker.checkManually()
        } label: {
            HStack(spacing: 6) {
                Color.clear.frame(width: 18, height: 1)
                if let update = updateChecker.availableUpdate {
                    Text(L10n.newVersionMenu(update.version))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Text("NEW")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Text(L10n.checkUpdatesMenu)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? rowID : (hoveredID == rowID ? nil : hoveredID)
        }
    }

    private func menuRow(
        id: String,
        title: String,
        shortcut: String? = nil,
        checked: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredID == id
        return Button(action: action) {
            HStack(spacing: 0) {
                ZStack {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 18, alignment: .leading)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let shortcut, !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? id : (hoveredID == id ? nil : hoveredID)
        }
    }

    private func confirmRemove(_ library: LunaLibraryStore.Library) {
        dismiss()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.lunaLibraryRemoveTitle
            alert.informativeText = L10n.lunaLibraryRemoveMessage(library.name)
            alert.addButton(withTitle: L10n.lunaLibraryRemove)
            alert.addButton(withTitle: L10n.cancel)
            if alert.runModal() == .alertFirstButtonReturn {
                libraryStore.remove(library)
                AppOrchestrator.shared.reloadLiveSessionIfUsingLuna()
            }
        }
    }
}
