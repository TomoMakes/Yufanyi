import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @AppStorage(LunaMissRecorder.enabledKey) private var recordMisses = false

    var body: some View {
        if AppOrchestrator.shared.liveHitStats?.showsLowRateWarning == true {
            Text(L10n.hitRateLowWarning)
            if !recordMisses {
                Button(L10n.missRecordMenuEnable) { recordMisses = true }
            }
            Divider()
        }

        Button(AppOrchestrator.shared.isLiveTranslating ? L10n.stopLiveTranslation : L10n.liveTranslateMenu) {
            AppOrchestrator.shared.toggleLiveTranslation()
        }
        .globalKeyboardShortcut(.liveTranslate)

        Button(L10n.settingsMenu) {
            AppOrchestrator.shared.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        if recordMisses {
            Button(L10n.feedbackCopy) {
                AppOrchestrator.shared.copyLunaFeedback()
            }
        }

        Button(L10n.contactAuthor) {
            AppOrchestrator.shared.showContact()
        }

        Button(L10n.aboutApp) {
            AppOrchestrator.shared.showAbout()
        }

        Divider()

        Button(L10n.quit) {
            NSApplication.shared.terminate(nil)
        }
    }
}
