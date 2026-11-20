import CoreGraphics
import Foundation
import Testing
@testable import ScreenTranslate

/// 실시간 번역 감시 세션 — 가짜 캡처·인식·번역으로 틱을 한 단계씩 진행한다.
@MainActor
@Suite struct LiveTranslationSessionTests {

    /// 세션과 가짜 의존성 묶음
    @MainActor
    final class Harness {
        let source = GatedFrameSource()
        let ocr: ScriptedOCRProvider
        let translator: TranslationProvider
        var busy = false
        var fallbackEnabled = false
        var fallbackReadiness: LiveTranslationSession.Readiness = .ready
        var sourceLanguage: Locale.Language?
        var readiness: LiveTranslationSession.Readiness = .ready
        private(set) var readinessChecks = 0
        var region = LiveRegion(rect: CGRect(x: 0, y: 0, width: 96, height: 24), displayID: 1, scale: 1)
        private(set) var stopReasons: [LiveTranslationSession.StopReason] = []
        private(set) var sleeps: [Duration] = []
        let misses = CollectingMissRecorder()
        private(set) var session: LiveTranslationSession!

        /// 기본 인자는 격리되지 않은 문맥에서 평가되므로 MainActor 가짜는 안에서 만든다
        init(ocr results: [String], translator: TranslationProvider? = nil,
             rescueVariants: [LiveImageVariants.Maker] = [],
             fallbackTranslator: TranslationProvider? = nil,
             fallbackEnabled: Bool = false) {
            ocr = ScriptedOCRProvider(results)
            self.translator = translator ?? RecordingTranslationProvider()
            self.fallbackEnabled = fallbackEnabled
            session = LiveTranslationSession(
                dependencies: .init(
                    frameSource: source,
                    ocr: ocr,
                    translator: self.translator,
                    isTranslatorBusy: { [unowned self] in self.busy },
                    checkReadiness: { [unowned self] _, _ in
                        self.readinessChecks += 1
                        return self.readiness
                    },
                    sleep: { @MainActor [weak self] duration in self?.sleeps.append(duration) },
                    missRecorder: misses,
                    rescueVariants: rescueVariants,
                    fallbackTranslator: fallbackTranslator,
                    fallbackEnabled: { [unowned self] in self.fallbackEnabled },
                    isFallbackBusy: { [unowned self] in self.busy },
                    checkFallbackReadiness: { [unowned self] _, _ in self.fallbackReadiness }
                ),
                region: { [unowned self] in self.region },
                languages: { [unowned self] in (self.sourceLanguage, Locale.Language(identifier: "ko")) },
                preprocess: { false }
            )
            session.onStop = { [unowned self] in self.stopReasons.append($0) }
        }

        var recorder: RecordingTranslationProvider {
            translator as! RecordingTranslationProvider
        }

        /// 한 틱: 캡처 요청을 기다렸다 화면을 주고, 틱이 끝나 다음 요청이 올 때까지 기다린다
        func feed(_ image: CGImage) async {
            await source.nextRequest()
            source.deliver(image)
            await source.nextRequest()
        }

        /// 비동기 번역이 끝나기를 잠깐 기다린다
        func settle(until condition: () -> Bool) async {
            for _ in 0..<200 where !condition() {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test("a stable subtitle is translated and shown")
    func showsStableSubtitle() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        await h.settle { h.session.display == .subtitle("번역:Hello") }
        #expect(h.session.display == .subtitle("번역:Hello"))
        #expect(h.recorder.requests == ["Hello"])
        #expect(h.session.translationCount == 1)
        h.session.stop(.user)
    }

    @Test("an unchanged screen skips text recognition once its subtitle is shown")
    func unchangedFrameSkipsOCR() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        let frame = TestImages.block(at: 0)
        // 第二次是真的再认一遍，用来确认字幕，不拿上一次的结果顶替
        await h.feed(frame)
        await h.feed(frame)
        await h.settle { h.session.display == .subtitle("번역:Hello") }
        for _ in 0..<3 {
            await h.feed(frame)
        }
        #expect(h.ocr.callCount == 2)
        h.session.stop(.user)
    }

    @Test("a missed subtitle is read again while the screen looks unchanged")
    func missIsReread() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\n化科"), .success("仁科译")]
        let h = Harness(ocr: ["化科", "化科", "仁科", "仁科"], translator: recorder)
        h.session.start()
        let frame = TestImages.block(at: 0)
        await h.feed(frame)
        await h.feed(frame)
        await h.settle { recorder.requests == ["化科"] }
        await h.feed(frame)
        await h.feed(frame)
        await h.settle { h.session.display == .subtitle("仁科译") }
        #expect(h.session.display == .subtitle("仁科译"))
        #expect(recorder.requests == ["化科", "仁科"])
        #expect(h.ocr.callCount == 4)
        h.session.stop(.user)
        // 同一句重认后命中了：不算未命中，不存画面
        #expect(h.misses.misses.isEmpty)
    }

    @Test("a line that stays missed is saved once, when the next line arrives")
    func finalMissIsSavedOnce() async {
        let recorder = RecordingTranslationProvider()
        // 同一句重认出的字没变，不会再查第二次库：第一句只有一次结果
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\n法えて"), .success("下一句译文")]
        let h = Harness(ocr: ["法えて", "法えて", "法えて", "法えて", "次の行", "次の行"], translator: recorder)
        h.session.start()
        let first = TestImages.block(at: 0)
        for _ in 0..<4 { await h.feed(first) }
        await h.settle { recorder.requests.count >= 1 }
        // 还停在这一句：先拿在手里，不存
        #expect(h.misses.misses.isEmpty)
        let second = TestImages.block(at: 60)
        await h.feed(second)
        await h.feed(second)
        await h.settle { h.session.display == .subtitle("下一句译文") }
        #expect(h.misses.misses.map(\.text) == ["法えて"])
        #expect(h.misses.misses.first?.image != nil)
        #expect(h.misses.misses.first?.output.contains(LunaHitStats.missMarker) == true)
        h.session.stop(.user)
        #expect(h.misses.misses.count == 1)
    }

    @Test("a half-typed line that the full line continues is not saved on its own")
    func typedPrefixIsNotSaved() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\n（こんな"), .success("\(LunaHitStats.missMarker)\n（こんな機会）")]
        let h = Harness(ocr: ["（こんな", "（こんな", "（こんな機会）", "（こんな機会）"], translator: recorder)
        h.session.start()
        let first = TestImages.block(at: 0)
        await h.feed(first)
        await h.feed(first)
        await h.settle { recorder.requests.count == 1 }
        let second = TestImages.block(at: 60)
        await h.feed(second)
        await h.feed(second)
        await h.settle { recorder.requests.count == 2 }
        await h.settle { h.session.display == .subtitle("\(LunaHitStats.missMarker)\n（こんな機会）") }
        h.session.stop(.user)
        #expect(h.misses.misses.map(\.text) == ["（こんな機会）"])
    }

    @Test("stopping saves the line that is still missed")
    func stopSavesHeldMiss() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\n法えて")]
        let h = Harness(ocr: ["法えて"], translator: recorder)
        h.session.start()
        let frame = TestImages.block(at: 0)
        await h.feed(frame)
        await h.feed(frame)
        await h.settle { h.session.display == .subtitle("\(LunaHitStats.missMarker)\n法えて") }
        #expect(h.misses.misses.isEmpty)
        h.session.stop(.user)
        #expect(h.misses.misses.map(\.text) == ["法えて"])
    }

    @Test("re-reading an unchanged screen stops after the limit")
    func rereadsAreLimited() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\n知らない")]
        let h = Harness(ocr: ["知らない"], translator: recorder)
        h.session.start()
        let frame = TestImages.block(at: 0)
        for _ in 0..<8 {
            await h.feed(frame)
            await h.settle { recorder.requests.count == 1 }
        }
        #expect(h.ocr.callCount == 1 + LiveTranslationSession.maxUnchangedRereads)
        #expect(recorder.requests == ["知らない"])
        h.session.stop(.user)
    }

    @Test("the next capture comes sooner while new text waits to be confirmed")
    func quickIntervalWhileUnsettled() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        let frame = TestImages.block(at: 0)
        await h.feed(frame)
        #expect(h.sleeps.last == .milliseconds(120))
        await h.feed(frame)
        await h.settle { h.session.display == .subtitle("번역:Hello") }
        await h.feed(frame)
        #expect(h.sleeps.last == .milliseconds(333))
        h.session.stop(.user)
    }

    @Test("an empty screen keeps the normal interval")
    func normalIntervalWhenEmpty() async {
        let h = Harness(ocr: [""])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 0))
        #expect(h.sleeps.allSatisfy { $0 == .milliseconds(333) })
        h.session.stop(.user)
    }

    @Test("a changed screen resets the re-read limit")
    func changedFrameResetsRereads() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\nA")]
        let h = Harness(ocr: ["A"], translator: recorder)
        h.session.start()
        for _ in 0..<5 {
            await h.feed(TestImages.block(at: 0))
            await h.settle { recorder.requests.count == 1 }
        }
        let before = h.ocr.callCount
        await h.feed(TestImages.block(at: 60))
        await h.feed(TestImages.block(at: 60))
        #expect(h.ocr.callCount == before + 2)
        h.session.stop(.user)
    }

    @Test("the same subtitle is not translated again")
    func doesNotRetranslate() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        for x in [0, 20, 40, 60] {
            await h.feed(TestImages.block(at: x))
        }
        await h.settle { !h.recorder.requests.isEmpty }
        #expect(h.recorder.requests == ["Hello"])
        h.session.stop(.user)
    }

    @Test("waits while another feature uses Apple Translation, then sends")
    func yieldsToOtherTranslations() async {
        let h = Harness(ocr: ["Hello"])
        h.busy = true
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        #expect(h.recorder.requests.isEmpty)
        h.busy = false
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.recorder.requests == ["Hello"] }
        #expect(h.recorder.requests == ["Hello"])
        h.session.stop(.user)
    }

    @Test("a request pushed out by another feature is retried")
    func retriesWhenSuperseded() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.failure(TranslationError.superseded), .success("안녕")]
        let h = Harness(ocr: ["Hello"], translator: recorder)
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        await h.settle { recorder.requests.count == 1 }
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.session.display == .subtitle("안녕") }
        #expect(recorder.requests == ["Hello", "Hello"])
        #expect(h.session.display == .subtitle("안녕"))
        h.session.stop(.user)
    }

    @Test("a late translation of an old subtitle is discarded")
    func dropsStaleTranslation() async {
        let gated = GatedTranslationProvider()
        let h = Harness(ocr: ["A", "A", "B", "B"], translator: gated)
        h.session.start()
        for x in [0, 20, 40, 60] {
            await h.feed(TestImages.block(at: x))
        }
        await h.settle { gated.pendingCount == 2 }
        gated.resumeFirst(with: .success("A번역"))
        await h.settle { gated.completedCalls == 1 }
        #expect(h.session.display != .subtitle("A번역"))
        gated.resumeFirst(with: .success("B번역"))
        await h.settle { h.session.display == .subtitle("B번역") }
        #expect(h.session.display == .subtitle("B번역"))
        h.session.stop(.user)
    }

    @Test("a failed translation shows the reason and is not retried")
    func failureIsNotRetried() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.failure(TranslationError.languageNotSupported)]
        let h = Harness(ocr: ["Hello"], translator: recorder)
        let reason = TranslationError.languageNotSupported.localizedDescription
        h.session.start()
        for x in [0, 20, 40, 60] {
            await h.feed(TestImages.block(at: x))
        }
        await h.settle { h.session.display == .message(reason) }
        #expect(h.session.display == .message(reason))
        #expect(recorder.requests == ["Hello"])
        h.session.stop(.user)
    }

    @Test("the subtitle bar hides when the subtitle disappears")
    func hidesWhenCleared() async {
        let h = Harness(ocr: ["Hello", "Hello", "", ""])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 20))
        await h.settle { h.session.display == .subtitle("번역:Hello") }
        await h.feed(TestImages.block(at: 40))
        await h.feed(TestImages.block(at: 60))
        #expect(h.session.display == .hidden)
        h.session.stop(.user)
    }

    @Test("an empty area at the start keeps the waiting message")
    func keepsWaitingMessage() async {
        let h = Harness(ocr: [""])
        h.session.start()
        #expect(h.session.display == .message(L10n.liveWaitingForText))
        for x in [0, 20, 40] {
            await h.feed(TestImages.block(at: x))
        }
        #expect(h.session.display == .message(L10n.liveWaitingForText))
        h.session.stop(.user)
    }

    @Test("a capture failure stops the session with the reason")
    func captureFailureStops() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.source.nextRequest()
        h.source.fail(CaptureError.noDisplayFound)
        await h.settle { !h.session.isRunning }
        #expect(!h.session.isRunning)
        #expect(h.stopReasons == [.captureFailed(CaptureError.noDisplayFound.localizedDescription)])
        #expect(h.session.display == .hidden)
    }

    @Test("stopping twice reports once and clears the display")
    func stopIsIdempotent() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.source.nextRequest()
        h.session.stop(.user)
        h.session.stop(.user)
        #expect(h.stopReasons == [.user])
        #expect(!h.session.isRunning)
        #expect(h.session.display == .hidden)
    }

    @Test("with auto-detect, a subtitle whose language pack is missing shows a download hint instead of translating")
    func autoSourceMissingPack() async {
        let h = Harness(ocr: ["Hello"])
        h.readiness = .needsDownload
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        await h.settle { h.session.display == .message(L10n.liveSourcePackMissing) }
        #expect(h.session.display == .message(L10n.liveSourcePackMissing))
        #expect(h.recorder.requests.isEmpty)
        h.session.stop(.user)
    }

    @Test("with an explicit source language the readiness check is skipped — the pack was checked at start")
    func explicitSourceSkipsReadiness() async {
        let h = Harness(ocr: ["Hello"])
        h.sourceLanguage = Locale.Language(identifier: "en")
        h.readiness = .needsDownload
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 30))
        await h.settle { h.recorder.requests == ["Hello"] }
        #expect(h.recorder.requests == ["Hello"])
        #expect(h.readinessChecks == 0)
        h.session.stop(.user)
    }

    @Test("each tick captures the region where it is now")
    func followsRegionChanges() async {
        let h = Harness(ocr: ["Hello"])
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        let moved = LiveRegion(rect: CGRect(x: 50, y: 50, width: 96, height: 24), displayID: 1, scale: 1)
        h.region = moved
        await h.feed(TestImages.block(at: 20))
        #expect(h.source.requestedRegions.last == moved)
        h.session.stop(.user)
    }

    // MARK: - 2026-11-14 换图重认、无日文、重认次数、命中统计

    private func luna(_ rows: [(String, String)]) throws -> LunaPretranslationProvider {
        LunaPretranslationProvider(path: try LunaTestDatabase.make(rows))
    }

    @Test("a missed line is read again from a treated copy of the same frame, and a full match is used")
    func rescueVariantTurnsAMissIntoAHit() async throws {
        // 前两次读原图（读歪），第三次是换了处理的那一帧（读对）
        let h = Harness(ocr: ["「そう、完気が出たみたいで良かった」", "「そう、完気が出たみたいで良かった」",
                              "「そう、元気が出たみたいで良かった」"],
                        translator: try luna([("「そう、元気が出たみたいで良かった」", "译文")]),
                        rescueVariants: [{ $0 }])
        h.session.start()
        let frame = TestImages.block(at: 0)
        await h.feed(frame)
        await h.feed(frame)
        await h.settle { h.session.display == .subtitle("译文") }
        #expect(h.session.display == .subtitle("译文"))
        #expect(h.ocr.callCount == 3)
        #expect(h.session.hitStats.hits == 1)
        #expect(h.session.hitStats.misses == 0)
        // 已经命中：画面没变也不再重认
        await h.feed(frame)
        #expect(h.ocr.callCount == 3)
        h.session.stop(.user)
        #expect(h.misses.misses.isEmpty)
    }

    @Test("a treated copy that still misses leaves the line missed")
    func rescueThatMissesKeepsTheMiss() async throws {
        let h = Harness(ocr: ["「知らない台詞です」"],
                        translator: try luna([("「そう、元気が出たみたいで良かった」", "译文")]),
                        rescueVariants: [{ $0 }, { _ in nil }])
        h.session.start()
        let frame = TestImages.block(at: 0)
        await h.feed(frame)
        await h.feed(frame)
        await h.settle { h.session.hitStats.total == 1 }
        #expect(h.session.display == .subtitle("\(LunaHitStats.missMarker)\n「知らない台詞です」"))
        #expect(h.session.hitStats.misses == 1)
        h.session.stop(.user)
        #expect(h.misses.misses.map(\.text) == ["「知らない台詞です」"])
    }

    @Test("text without any Japanese hides the bar and is neither counted nor saved")
    func foreignTextIsIgnored() async throws {
        let h = Harness(ocr: ["「はい」", "「はい」", "TLI", "TLI"], translator: try luna([("「はい」", "是的")]))
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 0))
        await h.settle { h.session.display == .subtitle("是的") }
        await h.feed(TestImages.block(at: 60))
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.session.display == .hidden }
        #expect(h.session.display == .hidden)
        #expect(h.session.hitStats.total == 1)
        h.session.stop(.user)
        #expect(h.misses.misses.isEmpty)
    }

    @Test("re-reading goes on while each reading differs from the last one")
    func rereadsContinueWhileTheTextKeepsChanging() async {
        let recorder = RecordingTranslationProvider()
        recorder.outcomes = [.success("\(LunaHitStats.missMarker)\n最後")]
        // 字还在淡入：同一块画面连着读出五种不同的字，最后才稳定
        let h = Harness(ocr: ["読み1", "読み2", "読み3", "読み4", "読み5", "最後"], translator: recorder)
        h.session.start()
        let frame = TestImages.block(at: 0)
        for _ in 0..<12 { await h.feed(frame) }
        await h.settle { recorder.requests == ["最後"] }
        #expect(recorder.requests == ["最後"])
        // 5 次读法在变 + 稳定后的一次确认 + 没命中的 3 次重认
        #expect(h.ocr.callCount == 6 + LiveTranslationSession.maxUnchangedRereads)
        h.session.stop(.user)
    }

    @Test("a screen whose reading never settles stops being re-read at the screen limit")
    func rereadsOfOneScreenAreCapped() async {
        let h = Harness(ocr: (0..<60).map { "読み\($0)" })
        h.session.start()
        let frame = TestImages.block(at: 0)
        for _ in 0..<40 { await h.feed(frame) }
        #expect(h.ocr.callCount == 1 + LiveTranslationSession.maxScreenRereads + LiveTranslationSession.maxUnchangedRereads - 1)
        h.session.stop(.user)
    }

    @Test("a new line confirmed by its second frame does not cancel the previous line's miss")
    func aNewLineKeepsThePreviousMissCounted() async throws {
        let h = Harness(ocr: ["「知らない台詞です」", "「知らない台詞です」", "「はい」", "「はい」"],
                        translator: try luna([("「はい」", "是的"), ("「長い台詞がここにあります」", "长")]))
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 0))
        await h.settle { h.session.hitStats.total == 1 }
        #expect(h.session.hitStats.misses == 1)
        await h.feed(TestImages.block(at: 60))
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.session.display == .subtitle("是的") }
        #expect(h.session.hitStats.hits == 1)
        #expect(h.session.hitStats.misses == 1)
        h.session.stop(.user)
    }

    @Test("fallback translator displays marked translation on miss while preserving miss stats and recording")
    func fallbackOnMissDisplaysMarkedTranslationAndKeepsMissRecord() async throws {
        let fallback = RecordingTranslationProvider()
        fallback.outcomes = [.success("「鸫，我们回去吧」")]
        let h = Harness(
            ocr: ["「ツグミ、さぁ帰ろう」", "「ツグミ、さぁ帰ろう」"],
            translator: try luna([("「はい」", "是的")]),
            fallbackTranslator: fallback,
            fallbackEnabled: true
        )
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 0))
        await h.settle { h.session.hitStats.total == 1 }
        #expect(h.session.display == .subtitle("\(L10n.lunaFallbackPrefix)\n「鸫，我们回去吧」"))
        #expect(h.session.hitStats.misses == 1)
        #expect(h.session.hitStats.hits == 0)
        h.session.stop(.user)
        #expect(h.misses.misses.count == 1)
        #expect(h.misses.misses.first?.output.hasPrefix(LunaHitStats.missMarker) == true)
    }

    @Test("fallback stays silent and shows normal miss when pack is missing or toggle is off")
    func fallbackFallsBackGracefullyWhenUnavailable() async throws {
        let fallback = RecordingTranslationProvider()
        fallback.outcomes = [.success("不会显示")]
        let h = Harness(
            ocr: ["「ツグミ、さぁ帰ろう」", "「ツグミ、さぁ帰ろう」"],
            translator: try luna([("「はい」", "是的")]),
            fallbackTranslator: fallback,
            fallbackEnabled: true
        )
        h.fallbackReadiness = .needsDownload
        h.session.start()
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 0))
        await h.settle { h.session.hitStats.total == 1 }
        #expect(h.session.display == .subtitle("\(LunaHitStats.missMarker)\n「ツグミ、さぁ帰ろう」"))
        #expect(fallback.requests.isEmpty)
        h.session.stop(.user)
    }

    @Test("on AUTO a one-frame line with garbled leading dots/dash translates immediately without waiting for a repeat")
    func autoOneFrameLeadingSymbolShortcut() async throws {
        let translator = try luna([
            ("「はい」", "是的"),
            ("「……——大丈夫、悪人ではないわ」", "「……——放心吧，她不是坏人」"),
            ("「次の行」", "「下一行」"),
        ])
        let h = Harness(
            ocr: ["「はい」", "「はい」", "・・・・・・大丈夫、悪人ではないわ」", "「次の行」"],
            translator: translator
        )
        h.session.start()
        // 第一句先让数据库加载完
        await h.feed(TestImages.block(at: 0))
        await h.feed(TestImages.block(at: 0))
        await h.settle { h.session.display == .subtitle("是的") }
        // AUTO 下仅出现一帧的台词（且丢了「和——」），必须当场出译文
        await h.feed(TestImages.block(at: 30))
        await h.settle { h.session.display == .subtitle("「……——放心吧，她不是坏人」") }
        #expect(h.session.display == .subtitle("「……——放心吧，她不是坏人」"))
        // 下一帧已经切到下一句，同样单帧切走
        await h.feed(TestImages.block(at: 60))
        await h.settle { h.session.display == .subtitle("「下一行」") }
        #expect(h.session.display == .subtitle("「下一行」"))
        h.session.stop(.user)
    }
}
