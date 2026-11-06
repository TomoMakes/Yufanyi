import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Button(AppOrchestrator.shared.isLiveTranslating ? L10n.stopLiveTranslation : L10n.liveTranslateMenu) {
            AppOrchestrator.shared.toggleLiveTranslation()
        }
        .globalKeyboardShortcut(.liveTranslate)

        Divider()

        Button(L10n.aboutApp) {
            AppOrchestrator.shared.showAbout()
        }

        Button(L10n.settingsMenu) {
            AppOrchestrator.shared.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(L10n.quit) {
            NSApplication.shared.terminate(nil)
        }
    }
}
