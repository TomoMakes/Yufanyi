import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            Text("预翻译 for Mac")
                .font(.title2.bold())

            VStack(spacing: 4) {
                Text(L10n.aboutVersion(AppVersion.fullVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(L10n.aboutCopyright)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 6) {
                Text("基于 ScreenTranslate 修改，以 GPLv3 协议发布")
                Link("ScreenTranslate 原项目（GitHub）", destination: URL(string: "https://github.com/hcmhcs/screenTranslate")!)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 16)
    }
}
