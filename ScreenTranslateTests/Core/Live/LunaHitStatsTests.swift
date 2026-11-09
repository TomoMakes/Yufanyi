import Testing
@testable import ScreenTranslate

/// 运行时命中率统计
@Suite struct LunaHitStatsTests {
    private let miss = LunaHitStats.missMarker

    @Test func emptyHasNoSummaryAndNoWarning() {
        let stats = LunaHitStats()
        #expect(stats.total == 0)
        #expect(stats.summary == nil)
        #expect(!stats.showsLowRateWarning)
    }

    @Test func classifiesHitPartialAndMiss() {
        var stats = LunaHitStats()
        stats.record(source: "「本当だ！」", output: "「真的！」")
        stats.record(source: "名前\n「台詞」", output: "\(miss)\n名前\n\n「台词」")
        stats.record(source: "知らない文", output: "\(miss)\n知らない文")
        #expect(stats.hits == 1)
        #expect(stats.partials == 1)
        #expect(stats.misses == 1)
        #expect(stats.summary == "命中 67%")
    }

    @Test func missWithOnlyMissSegmentsIsAMiss() {
        var stats = LunaHitStats()
        stats.record(source: "a\n\nb", output: "\(miss)\na\n\n\(miss)\nb")
        #expect(stats.misses == 1)
        #expect(stats.partials == 0)
    }

    @Test func sameSourceInARowCountsOnce() {
        var stats = LunaHitStats()
        let first = stats.record(source: "「同じ」", output: "「相同」")
        let repeated = stats.record(source: "「同じ」 ", output: "「相同」")
        let next = stats.record(source: "「次」", output: "「下一句」")
        let back = stats.record(source: "「同じ」", output: "「相同」")
        #expect(first && !repeated && next && back)
        #expect(stats.total == 3)
    }

    @Test func emptySourceIsIgnored() {
        var stats = LunaHitStats()
        let counted = stats.record(source: "  \n", output: "")
        #expect(!counted)
        #expect(stats.total == 0)
    }

    @Test func warnsOnlyAfterEnoughLinesWithLowRate() {
        var stats = LunaHitStats()
        for i in 0..<9 { stats.record(source: "miss \(i)", output: "\(miss)\nmiss \(i)") }
        #expect(!stats.showsLowRateWarning)  // 9 句，还不够
        stats.record(source: "miss 9", output: "\(miss)\nmiss 9")
        #expect(stats.showsLowRateWarning)    // 10 句，0%
        for i in 0..<5 { stats.record(source: "hit \(i)", output: "译文 \(i)") }
        #expect(!stats.showsLowRateWarning)   // 5/15 ≈ 33%，不再提示
    }

    @Test func rereadCorrectsTheLastMiss() {
        var stats = LunaHitStats()
        stats.record(source: "「前」", output: "「之前」")
        stats.record(source: "「化科さん」", output: "\(miss)\n「化科さん」")
        stats.record(source: "「仁科さん」", output: "「仁科先生」", correctsLastMiss: true)
        #expect(stats.hits == 2)
        #expect(stats.misses == 0)
        #expect(stats.total == 2)
    }

    @Test func rereadDoesNotTouchAnEarlierHit() {
        var stats = LunaHitStats()
        stats.record(source: "「一」", output: "「一译」")
        stats.record(source: "「二」", output: "「二译」", correctsLastMiss: true)
        #expect(stats.hits == 2)
        #expect(stats.total == 2)
        // 重认之后还是没命中：同一句台词仍只记一次未命中
        stats.record(source: "「三」", output: "\(miss)\n「三」")
        stats.record(source: "「三'」", output: "\(miss)\n「三'」", correctsLastMiss: true)
        #expect(stats.misses == 1)
        #expect(stats.total == 3)
    }
}
