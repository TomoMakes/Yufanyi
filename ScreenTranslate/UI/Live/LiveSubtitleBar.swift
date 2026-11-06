import AppKit
import SwiftUI

/// 실시간 번역 결과를 영역 옆에 보여주는 자막 바 — 클릭을 통과시키고 포커스를 빼앗지 않는다.
final class LiveSubtitleBar: NSPanel {
    private let hostingView = NSHostingView(
        rootView: LiveSubtitleView(display: .hidden, width: LiveLayout.barMinWidth, heightLimit: nil)
    )
    private var currentText = ""
    private var fullTextPanel: NSPanel?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
    }

    func update(display: LiveTranslationSession.Display, regionFrame: CGRect, visibleFrame: CGRect) {
        guard display != .hidden else {
            currentText = ""
            fadeOut()
            return
        }
        let width = LiveLayout.subtitleBarWidth(regionWidth: regionFrame.width, visibleFrame: visibleFrame)
        switch display {
        case .subtitle(let text), .message(let text): currentText = text
        case .hidden: currentText = ""
        }
        hostingView.rootView = LiveSubtitleView(display: display, width: width, heightLimit: nil)
        let naturalSize = hostingView.fittingSize
        let maximumHeight = max(60, min(visibleFrame.height * 0.35, visibleFrame.height - 32))
        let truncated = naturalSize.height > maximumHeight
        hostingView.rootView = LiveSubtitleView(display: display, width: width,
                                               heightLimit: truncated ? maximumHeight : nil)
        let size = CGSize(width: width, height: min(naturalSize.height, maximumHeight))
        setFrame(LiveLayout.subtitleBarFrame(regionFrame: regionFrame, barSize: size,
                                             toolbarHeight: LiveRegionWindow.toolbarSize.height,
                                             visibleFrame: visibleFrame), display: true)
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func showFullText() {
        guard !currentText.isEmpty else { return }
        fullTextPanel?.close()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 420),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = L10n.liveFullTextSnapshot
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.font = .systemFont(ofSize: AppSettings.shared.popupFontSize + 6)
        text.string = currentText
        scroll.documentView = text
        panel.contentView = scroll
        panel.center()
        fullTextPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    override func close() {
        fullTextPanel?.close()
        fullTextPanel = nil
        super.close()
    }

    private func fadeOut() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // NSAnimationContext 완료 핸들러는 메인 스레드에서 불리지만 @Sendable로 선언되어 있다
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}

private struct LiveSubtitleView: View {
    let display: LiveTranslationSession.Display
    let width: CGFloat
    let heightLimit: CGFloat?

    var body: some View {
        VStack(spacing: 4) {
            content
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: heightLimit.map { max(20, $0 - 56) }, alignment: .top)
                .clipped()
            if heightLimit != nil {
                Text(L10n.liveMoreText).font(.caption).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: width, height: heightLimit)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch display {
        case .subtitle(let text):
            Text(text)
                .font(.system(size: AppSettings.shared.popupFontSize + 6))  // 字幕字体固定系统字体（字体选择以后作为收费功能）
                .foregroundStyle(.white)
        case .message(let text):
            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
        case .hidden:
            EmptyView()
        }
    }
}
