import AppKit
import SwiftUI

/// 「联系作者 / 获取更新」小窗：小红书、百度网盘（长期有效 + 二维码）、邮箱、GitHub。
enum ContactInfo {
    static let socialName = "TomoMakes_"
    static let baiduPanCode = "i6r8"
    static let baiduPanURL = URL(string: "https://pan.baidu.com/s/1gVOUwDNnaakvlkr5h8_QHg?pwd=i6r8")!
    static let email = "Gotosleepat9pm@gmail.com"
    static let githubReleases = URL(string: "https://github.com/TomoMakes/Yufanyi/releases")!
    static let githubIssues = URL(string: "https://github.com/TomoMakes/Yufanyi/issues")!
}

struct ContactView: View {
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.contactIntro)
                .font(.callout)
                .foregroundStyle(.secondary)

            // 小红书
            card {
                HStack(spacing: 12) {
                    iconBadge(systemName: "person.crop.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.contactSocialTitle(ContactInfo.socialName))
                            .font(.headline)
                        Text(L10n.contactSocialDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copiedID == "xiaohongshu" ? L10n.copied : L10n.contactCopyName) {
                        copy(ContactInfo.socialName, id: "xiaohongshu")
                    }
                }
            }

            // 百度网盘（长期有效 + 二维码）
            card {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            iconBadge(systemName: "arrow.down.circle")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.contactBaiduTitle)
                                    .font(.headline)
                                Text(L10n.contactBaiduDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text(L10n.contactBaiduCodeLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(ContactInfo.baiduPanCode)
                                        .font(.caption.monospaced().weight(.semibold))
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .padding(.top, 2)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(L10n.contactBaiduOpen) {
                                NSWorkspace.shared.open(ContactInfo.baiduPanURL)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(copiedID == "baiducode" ? L10n.copied : L10n.contactBaiduCopyCode) {
                                copy(ContactInfo.baiduPanCode, id: "baiducode")
                            }
                        }
                        .padding(.leading, 40)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        Image("BaiduPanQR")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 86, height: 86)
                            .padding(4)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                            )
                        Text(L10n.contactBaiduQRCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 邮箱
            card {
                HStack(spacing: 12) {
                    iconBadge(systemName: "envelope")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.contactEmailTitle)
                            .font(.headline)
                        Text(ContactInfo.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(copiedID == "email" ? L10n.copied : L10n.copy) {
                        copy(ContactInfo.email, id: "email")
                    }
                    if let mailto = URL(string: "mailto:\(ContactInfo.email)") {
                        Button(L10n.contactWriteEmail) {
                            NSWorkspace.shared.open(mailto)
                        }
                    }
                }
            }

            // GitHub
            card {
                HStack(spacing: 12) {
                    iconBadge(systemName: "chevron.left.forwardslash.chevron.right")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.contactGitHubTitle)
                            .font(.headline)
                        Text(L10n.contactGitHubDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.contactDownload) {
                        NSWorkspace.shared.open(ContactInfo.githubReleases)
                    }
                    Button(L10n.contactReportIssue) {
                        NSWorkspace.shared.open(ContactInfo.githubIssues)
                    }
                }
            }

            Text(L10n.contactVersionHint(AppVersion.fullVersion))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
            )
    }

    private func iconBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = id
    }
}
