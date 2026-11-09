import AppKit
import SwiftUI

/// 「联系作者」小窗里列出的联系方式（从菜单栏下拉菜单进入，以小窗列出各渠道供选择）。
/// 加新的联系方式：在 `channels` 里加一条。
enum ContactInfo {
    /// 小红书为主（B站、抖音同名）；只放账号名不放链接，换链接不用发新版
    static let socialName = "TomoMakes_"
    /// 夸克群：最新版发在这里，进群自取
    static let quarkGroupID = "111871874"
    static let githubIssues = URL(string: "https://github.com/TomoMakes/Yufanyi/issues")!
    /// 下载页指向 Releases 列表（测试版是预发布版，不计入 latest）
    static let githubReleases = URL(string: "https://github.com/TomoMakes/Yufanyi/releases")!
    /// 对外联系邮箱（与小红书主页公开的一致）；nil 时不显示邮件这一项。
    static let email: String? = "Gotosleepat9pm@gmail.com"

    struct Channel: Identifiable {
        enum Action {
            case open(URL)
            case copy(String)
        }
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let actions: [(label: String, action: Action)]
    }

    static var channels: [Channel] {
        // 顺序：小红书（主）→ 夸克群 → 邮件 → GitHub
        var list = [
            Channel(id: "xiaohongshu", symbol: "person.crop.circle", title: L10n.contactSocialTitle(socialName),
                    detail: L10n.contactSocialDetail, actions: [(L10n.contactCopyName, .copy(socialName))]),
            Channel(id: "quark", symbol: "person.3", title: L10n.contactQuarkTitle(quarkGroupID),
                    detail: L10n.contactQuarkDetail, actions: [(L10n.contactCopyGroupID, .copy(quarkGroupID))]),
        ]
        if let email, let mailto = URL(string: "mailto:\(email)") {
            list.append(Channel(id: "email", symbol: "envelope", title: L10n.contactEmailTitle, detail: email,
                                actions: [(L10n.copy, .copy(email)), (L10n.contactWriteEmail, .open(mailto))]))
        }
        // 不只是反馈：最新版和源码也在这里，只是英文网站、提交问题要账号，所以放最后
        list.append(Channel(id: "github", symbol: "chevron.left.forwardslash.chevron.right", title: L10n.contactGitHubTitle,
                            detail: L10n.contactGitHubDetail,
                            actions: [(L10n.contactDownload, .open(githubReleases)), (L10n.contactReportIssue, .open(githubIssues))]))
        return list
    }
}

struct ContactView: View {
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.contactIntro)
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(ContactInfo.channels) { channel in
                HStack(spacing: 10) {
                    Image(systemName: channel.symbol)
                        .font(.title3)
                        .frame(width: 24)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.title)
                        Text(channel.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    ForEach(Array(channel.actions.enumerated()), id: \.offset) { _, item in
                        Button(copiedID == channel.id && isCopy(item.action) ? L10n.copied : item.label) {
                            perform(item.action, channelID: channel.id)
                        }
                    }
                }
            }

            Text(L10n.contactVersionHint(AppVersion.fullVersion))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func isCopy(_ action: ContactInfo.Channel.Action) -> Bool {
        if case .copy = action { return true }
        return false
    }

    private func perform(_ action: ContactInfo.Channel.Action, channelID: String) {
        switch action {
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedID = channelID
        }
    }
}
