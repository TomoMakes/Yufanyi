import CoreGraphics
import Foundation
import Observation

/// 실시간 자막 번역의 감시 루프 (PR #4 아이디어를 베타로 재구현).
/// 캡처 → 화면 변화 확인 → 글자 인식 → 안정화 → Apple 번역 → 표시를 주기마다 반복한다.
/// 의존성을 모두 주입받아 가짜 캡처·인식·번역으로 테스트한다.
@MainActor @Observable
final class LiveTranslationSession {
    struct Dependencies {
        var frameSource: LiveFrameSource
        var ocr: OCRProvider
        var translator: TranslationProvider
        /// Apple 번역 브리지가 요청을 처리 중인지 — 자기 요청이 없는데 true면 다른 기능이 쓰는 중이다
        var isTranslatorBusy: () -> Bool
        /// 원문이 자동 감지일 때 자막 언어가 목표 언어로 바로 번역되는지 — 언어팩이 없으면 보이지 않는 창에
        /// 다운로드 창이 걸려 요청이 조용히 멈추므로 보내기 전에 확인한다 (운영: LanguageAvailability)
        var checkReadiness: (String, Locale.Language) async -> Readiness = { _, _ in .ready }
        var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        var interval: Duration = .milliseconds(333)
        /// 字刚变、还没定下来时的间隔：第二次确认来得快，AUTO 下停留很短的句子也来得及出字幕
        var quickInterval: Duration = .milliseconds(120)
        /// 自动保存未命中画面（只在用预翻译库时给）；开关由记录器自己现查
        var missRecorder: LunaMissRecording?
        /// 预翻译没命中时，把这一帧换几种处理再认（LiveImageVariants）；整句对上库才采用。空 = 不做
        var rescueVariants: [LiveImageVariants.Maker] = []
        /// 预翻译未命中时的兜底翻译器（仅在用预翻译库时注入；由 fallbackEnabled 控制开关）
        var fallbackTranslator: TranslationProvider? = nil
        var fallbackEnabled: () -> Bool = { false }
        var isFallbackBusy: () -> Bool = { false }
        var checkFallbackReadiness: (Locale.Language, Locale.Language) async -> Readiness = { _, _ in .ready }
    }

    enum Display: Equatable {
        case hidden
        case subtitle(String)
        case message(String)
    }

    enum Readiness: Equatable, Sendable {
        case ready
        case needsDownload
        case unsupported
    }

    /// 언어팩이 없어 번역을 보내지 않은 경우의 안내
    nonisolated enum ReadinessError: LocalizedError {
        case needsDownload

        var errorDescription: String? { L10n.liveSourcePackMissing }
    }

    /// 画面没变时最多重新识别几次。库里本来没有的句子，重认几次还是同样的字，就不再耗电重认。
    static let maxUnchangedRereads = 3
    /// 重认读出的字和上一次不一样，说明字还在淡入、打出，次数重新数；一屏里这样重数最多到这么多次。
    /// 2026-11-14 Money Parasite：3 次额度在字显示完之前用完，定格在半截的读法上
    /// （存下来的画面是干净的，重放 129 张里有 18 张原样就能命中）。
    static let maxScreenRereads = 12

    /// 一次识别的来历：第几次变化的文字、是不是画面没变时的重新识别
    struct ReadInfo: Equatable {
        var serial: Int
        var isReread: Bool
    }

    enum StopReason: Equatable {
        case user
        case screenLocked
        case displayRemoved
        case betaDisabled
        case captureFailed(String)
    }

    private(set) var display: Display = .hidden
    private(set) var isRunning = false
    private(set) var translationCount = 0
    /// 预翻译命中统计（只在用 Luna 预翻译库时记录）
    private(set) var hitStats = LunaHitStats()
    @ObservationIgnored var onHitStatsChange: ((LunaHitStats) -> Void)?
    @ObservationIgnored var onDisplayChange: ((Display) -> Void)?
    @ObservationIgnored var onStop: ((StopReason) -> Void)?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let region: () -> LiveRegion?
    @ObservationIgnored private let languages: () -> (source: Locale.Language?, target: Locale.Language)
    @ObservationIgnored private let preprocess: () -> Bool

    @ObservationIgnored private var stabilizer = LiveTextStabilizer()
    @ObservationIgnored private var lastFingerprint: FrameFingerprint?
    @ObservationIgnored private var lastRecognized: String?
    /// Luna only: Vision's lower-ranked readings of the latest frame, keyed by line text.
    @ObservationIgnored private var lastAlternates: [String: [String]] = [:]
    @ObservationIgnored private var pendingText: String?
    /// 等着翻译的那句来自哪一次识别
    @ObservationIgnored private var pendingRead = ReadInfo(serial: 0, isReread: false)
    /// 等着翻译的那句是从哪一帧画面认出来的（存未命中画面用）
    @ObservationIgnored private var pendingFrame: CGImage?
    /// 画面每变一次加一（重认不加）：判断两次结果是不是同一屏
    @ObservationIgnored private var screenSerial = 0
    @ObservationIgnored private var pendingScreen = 0
    /// 当前这一屏的未命中先拿在手里：同一屏重认命中了就丢掉，重认还没中就换成新的一帧；
    /// 换屏、字幕消失、停止时才真正存下来，一句只存一次。
    @ObservationIgnored private var heldMiss: (miss: LunaMiss, screen: Int)?
    /// 识别出的文字每变一次加一；翻译回来时据此判断它还是不是画面上最新的那句
    @ObservationIgnored private var readSerial = 0
    /// 最近识别的文字是否已经定下来：出过命中的字幕，或者画面里没有字。
    /// 没定下来时，画面看着没变也要重新识别——字还在打出、淡入时截到的那一帧可能认错，
    /// 不能拿上一次的结果冒充第二次确认，也不能一直沿用认错的字。
    @ObservationIgnored private var lastReadSettled = false
    /// 画面没变却因为没定下来而重新识别的次数；画面一变就清零
    @ObservationIgnored private var unchangedRereads = 0
    /// 这一屏总共重认了几次（含读法变了重新数的）；画面一变就清零
    @ObservationIgnored private var screenRereads = 0
    /// 上一次记进命中统计的是哪一屏
    @ObservationIgnored private var lastStatsScreen: Int?
    /// 各种图片处理救回过几句：救得多的先试
    @ObservationIgnored private var rescueWins: [Int] = []
    @ObservationIgnored private var hasShownSubtitle = false
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var translationTask: Task<Void, Never>?
    @ObservationIgnored private var translationToken = UUID()

    init(
        dependencies: Dependencies,
        region: @escaping () -> LiveRegion?,
        languages: @escaping () -> (source: Locale.Language?, target: Locale.Language),
        preprocess: @escaping () -> Bool
    ) {
        self.dependencies = dependencies
        self.region = region
        self.languages = languages
        self.preprocess = preprocess
    }

    func start() {
        guard !isRunning else { return }
        (dependencies.translator as? LunaPretranslationProvider)?.resetContext()
        stabilizer = LiveTextStabilizer()
        lastFingerprint = nil
        lastRecognized = nil
        lastAlternates = [:]
        lastReadSettled = false
        unchangedRereads = 0
        screenRereads = 0
        lastStatsScreen = nil
        rescueWins = Array(repeating: 0, count: dependencies.rescueVariants.count)
        heldMiss = nil
        pendingFrame = nil
        hitStats = LunaHitStats()
        onHitStatsChange?(hitStats)
        isRunning = true
        setDisplay(.message(L10n.liveWaitingForText))
        loopTask = Task { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                await self.tick()
                do {
                    try await self.dependencies.sleep(self.nextInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// 여러 번 불러도 한 번만 정리하고 알린다
    func stop(_ reason: StopReason) {
        guard isRunning else { return }
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
        cancelTranslation()
        pendingText = nil
        pendingFrame = nil
        saveHeldMiss()
        (dependencies.translator as? LunaPretranslationProvider)?.resetContext()
        setDisplay(.hidden)
        onStop?(reason)
    }

    /// 한 번의 감시 — 루프가 주기마다 부른다
    func tick() async {
        guard isRunning, let region = region() else { return }
        let image: CGImage
        do {
            image = try await dependencies.frameSource.captureFrame(of: region)
        } catch is CancellationError {
            return
        } catch {
            stop(.captureFailed(error.localizedDescription))
            return
        }
        guard isRunning, let read = await recognizeIfChanged(image), isRunning else { return }
        let (recognized, isReread) = read

        // Luna needs the layout boundaries. Its own normalization handles wrapped lines.
        let isLuna = dependencies.translator is LunaPretranslationProvider
        let text = preprocess() && !isLuna ? TranslationCoordinator.preprocessOCRText(recognized) : recognized
        let trusted = (dependencies.translator as? LunaPretranslationProvider)?
            .isCompleteExactHit(text, lineAlternates: lastAlternates) ?? false
        switch stabilizer.ingest(text, preservingLineBreaks: isLuna, acceptImmediately: trusted) {
        case .show(let subtitle):
            cancelTranslation()
            pendingText = subtitle
            pendingRead = ReadInfo(serial: readSerial, isReread: isReread)
            pendingFrame = image
            pendingScreen = screenSerial
        case .clear:
            cancelTranslation()
            pendingText = nil
            pendingFrame = nil
            saveHeldMiss()
            if hasShownSubtitle { setDisplay(.hidden) }
        case nil:
            break
        }
        startPendingTranslationIfPossible()
    }

    // MARK: - Private

    /// 字还没定下来（刚变、等确认，或没命中、还能重认）时缩短下一次截图的间隔
    private var nextInterval: Duration {
        let waiting = lastRecognized != nil && !lastReadSettled && unchangedRereads < Self.maxUnchangedRereads
        return waiting ? dependencies.quickInterval : dependencies.interval
    }

    private func setDisplay(_ newValue: Display) {
        guard display != newValue else { return }
        display = newValue
        onDisplayChange?(newValue)
    }

    /// 화면이 직전과 거의 같으면 인식을 건너뛰고 직전 결과를 쓴다. 인식이 실패하면 이번 틱은 건너뛴다(nil).
    /// 画面没变但上一次的字还没定下来（没出字幕或没命中）时，最多再认 maxUnchangedRereads 次。
    /// 返回的 isReread 表示这次是画面没变时的重新识别。
    private func recognizeIfChanged(_ image: CGImage) async -> (String, Bool)? {
        let fingerprint = FrameFingerprint(image: image)
        var isReread = false
        if let fingerprint, let lastFingerprint, let lastRecognized,
           fingerprint.isNearlyIdentical(to: lastFingerprint) {
            if lastReadSettled || unchangedRereads >= Self.maxUnchangedRereads {
                return (lastRecognized, false)
            }
            unchangedRereads += 1
            screenRereads += 1
            isReread = true
        } else {
            unchangedRereads = 0
            screenRereads = 0
            screenSerial += 1
        }
        let text: String
        do {
            let result = try await dependencies.ocr.recognize(image: image)
            let isLuna = dependencies.translator is LunaPretranslationProvider
            text = isLuna ? result.dialogueText : result.text
            lastAlternates = isLuna ? result.dialogueAlternates : [:]
        } catch OCRError.noTextFound {
            text = ""
            lastAlternates = [:]
        } catch {
            return nil
        }
        lastFingerprint = fingerprint
        if text != lastRecognized {
            readSerial += 1
            lastReadSettled = text.isEmpty
            // 画面看着没变、读出来的字却变了：还没显示完，接着认
            if isReread, screenRereads < Self.maxScreenRereads { unchangedRereads = 0 }
        }
        lastRecognized = text
        return (text, isReread)
    }

    private func startPendingTranslationIfPossible() {
        guard isRunning, let text = pendingText, translationTask == nil else { return }
        // 자기 요청이 없는데 브리지가 바쁘면 다른 기능(화면·빠른 번역)이 쓰는 중 — 사용자가 직접 한 번역이 우선
        guard !dependencies.isTranslatorBusy() else { return }
        pendingText = nil
        let read = pendingRead
        let frame = pendingFrame
        let screen = pendingScreen
        pendingFrame = nil
        let token = UUID()
        translationToken = token
        let (source, target) = languages()
        let translator = dependencies.translator
        let alternates = lastAlternates
        let checkReadiness = dependencies.checkReadiness
        let ocr = dependencies.ocr
        let variants = dependencies.rescueVariants
        let order = variants.indices.sorted { rescueWins[$0] > rescueWins[$1] }
        let fallbackTranslator = dependencies.fallbackTranslator
        let fallbackEnabled = dependencies.fallbackEnabled
        let isFallbackBusy = dependencies.isFallbackBusy
        let checkFallbackReadiness = dependencies.checkFallbackReadiness
        translationTask = Task { [weak self] in
            do {
                // 원문을 지정했으면 시작할 때 언어팩을 이미 확인했다
                if source == nil {
                    switch await checkReadiness(text, target) {
                    case .ready: break
                    case .needsDownload: throw ReadinessError.needsDownload
                    case .unsupported: throw TranslationError.languageNotSupported
                    }
                }
                var translated: String
                var displayText: String
                if let luna = translator as? LunaPretranslationProvider {
                    translated = try luna.translate(text: text, lineAlternates: alternates)
                    // 没命中：同一帧换一种处理再认，整句对上库才采用
                    if let frame, translated.isEmpty || translated.contains(LunaHitStats.missMarker) {
                        for index in order {
                            guard !Task.isCancelled else { break }
                            guard let variant = variants[index](frame),
                                  let reading = try? await ocr.recognize(image: variant) else { continue }
                            let rescued = try luna.translate(text: reading.dialogueText,
                                                             lineAlternates: reading.dialogueAlternates, isRescue: true)
                            if !rescued.isEmpty, !rescued.contains(LunaHitStats.missMarker) {
                                translated = rescued
                                self?.noteRescue(index)
                                break
                            }
                        }
                    }
                    displayText = translated
                    if translated.contains(LunaHitStats.missMarker),
                       let fallbackTranslator, fallbackEnabled(), !isFallbackBusy(), !Task.isCancelled {
                        let fallbackSource = source ?? Locale.Language(identifier: "ja")
                        if await checkFallbackReadiness(fallbackSource, target) == .ready, !Task.isCancelled,
                           let fallback = await Self.fallbackDisplayText(
                               for: translated, using: fallbackTranslator, from: fallbackSource, to: target
                           ) {
                            displayText = fallback
                        }
                    }
                } else {
                    translated = try await translator.translate(text: text, from: source, to: target)
                    displayText = translated
                }
                self?.finishTranslation(token, text: text, read: read, frame: frame, screen: screen,
                                        alternates: alternates, displayText: displayText, result: .success(translated))
            } catch {
                self?.finishTranslation(token, text: text, read: read, frame: frame, screen: screen,
                                        alternates: alternates, displayText: nil, result: .failure(error))
            }
        }
    }

    private func finishTranslation(_ token: UUID, text: String, read: ReadInfo, frame: CGImage?, screen: Int,
                                   alternates: [String: [String]], displayText: String?, result: Result<String, Error>) {
        guard token == translationToken else { return }  // 새 자막에 밀린 옛 결과
        translationTask = nil
        guard isRunning else { return }
        switch result {
        case .success(let translated):
            // 预翻译返回空：画面上没有日文（只有符号的句子被读成字母、模拟器的浮条、菜单外的画面），
            // 没东西可翻，不出字幕、不算未命中、不存。
            if translated.isEmpty, dependencies.translator is LunaPretranslationProvider {
                if read.serial == readSerial { lastReadSettled = true }
                if let held = heldMiss, held.screen != screen { saveHeldMiss() }
                if hasShownSubtitle { setDisplay(.hidden) }
                return
            }
            hasShownSubtitle = true
            translationCount += 1
            let missed = translated.contains(LunaHitStats.missMarker)
            // 画面上还是这句：命中就定下来，不再重认；没命中留着，画面没变也再认几次
            if read.serial == readSerial { lastReadSettled = !missed }
            if dependencies.missRecorder != nil {
                // 换了一屏：上一句已经过去，它的未命中现在存。还是同一屏（重认）：只留最后的结果。
                // 字还在一个个打出来时，没打完的半句被后面更长的那句接上，也不单独存。
                if let held = heldMiss, held.screen != screen, !Self.extends(held.miss.text, with: text) { saveHeldMiss() }
                heldMiss = missed
                    ? (LunaMiss(image: frame, text: text, alternates: alternates, output: translated), screen) : nil
            }
            if dependencies.translator is LunaPretranslationProvider {
                // 只有还是同一屏的重认，才撤掉上一次记的未命中；换了一屏就是另一句台词
                // （以前只看「是不是重认」，新的一句靠第二帧确认时会把上一句的未命中错撤掉）。
                let sameScreen = read.isReread && lastStatsScreen == screen
                if hitStats.record(source: text, output: translated, correctsLastMiss: sameScreen) {
                    lastStatsScreen = screen
                    onHitStatsChange?(hitStats)
                }
            }
            setDisplay(.subtitle(displayText ?? translated))
        case .failure(let error):
            if let translationError = error as? TranslationError, case .superseded = translationError {
                if pendingText == nil { pendingText = text; pendingRead = read; pendingFrame = frame; pendingScreen = screen }  // 다른 기능에 밀림 — 다음 틱에 다시
            } else if !(error is CancellationError) {
                // 같은 자막은 안정화기가 다시 내보내지 않으므로 재시도하지 않는다
                setDisplay(.message(error.localizedDescription))
            }
        }
    }

    private func noteRescue(_ index: Int) {
        if rescueWins.indices.contains(index) { rescueWins[index] += 1 }
    }

    /// 预翻译未命中时，对未命中的段落调用兜底翻译器，失败则保持原样不报错。
    private static func fallbackDisplayText(
        for lunaOutput: String,
        using fallback: TranslationProvider,
        from source: Locale.Language,
        to target: Locale.Language
    ) async -> String? {
        let missPrefix = LunaHitStats.missMarker + "\n"
        var segments = lunaOutput.components(separatedBy: "\n\n")
        var replaced = false
        for index in segments.indices {
            guard !Task.isCancelled else { return nil }
            let segment = segments[index]
            guard segment.hasPrefix(missPrefix) else { continue }
            let raw = String(segment.dropFirst(missPrefix.count))
            let cleaned = TranslationCoordinator.preprocessOCRText(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard let mt = try? await fallback.translate(text: cleaned, from: source, to: target) else { continue }
            let trimmed = mt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            segments[index] = L10n.lunaFallbackPrefix + "\n" + trimmed
            replaced = true
        }
        return replaced ? segments.joined(separator: "\n\n") : nil
    }

    private func saveHeldMiss() {
        guard let held = heldMiss else { return }
        heldMiss = nil
        dependencies.missRecorder?.record(held.miss)
    }

    /// `longer` 是不是 `shorter` 接着往下打出来的（忽略空白）
    private static func extends(_ shorter: String, with longer: String) -> Bool {
        let a = shorter.filter { !$0.isWhitespace }, b = longer.filter { !$0.isWhitespace }
        return !a.isEmpty && b.count > a.count && b.hasPrefix(a)
    }

    private func cancelTranslation() {
        translationToken = UUID()
        translationTask?.cancel()
        translationTask = nil
    }
}
