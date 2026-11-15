import Foundation
import Testing
@testable import ScreenTranslate

/// 2026-11-14 按 Money Parasite / DistortedCode 存下来的未命中画面加的匹配规则。
/// 每条规则一组正例（实际读歪的样子）和反例（有歧义时宁可不配）。
@Suite struct LunaFeedbackRulesTests {
    private let miss = "［预翻译未命中］"

    private let rows: [(String, String)] = [
        ("「相手の気持ちを、汲み取る……？」", "译1"),
        ("（そう、だったんだ……）", "译2"),
        ("黄さんの一言によって、私の初カジノが始まった――。", "译3"),
        ("「嫌ですが？」", "译4"),
        ("「！」", "译5"),
        ("二枚を変えた所で結果は同じだったけれど、役は『スリーカード』。", "译6"),
        ("「『かがみ』……？」", "译7"),
        ("……でも、彼も理解しているだろう。", "译8前。"),
        ("私のあの態度を見れば。", "译8后。"),
        ("「え……", "「译9前……"),
        ("えっ、もうこんな時間なのっ！？」", "译9后！？」"),
        ("（特にあの人との出会いは衝撃的だった……）", "译10"),
        ("「……え？」", "「……诶？」"),
        ("「…………え？」", "「…………诶？」"),
        ("「そう、元気が出たみたいで良かった」", "译12"),
        ("更にどうやらここには通常とは別の“ハイ＆ロウ”が存在しているらしい。", "译13"),
        ("「…………誰ですか」", "译14"),
        ("本当にそんな事が？", "译15"),
        ("「……う～ん、そうきますか」", "译16"),
        ("「君が不安がっていたらその気持ちも観客にバレてしまうだろうからね」", "译17"),
    ]

    private func provider(_ extra: [(String, String)] = [], lookAlike: Bool = false) throws -> LunaPretranslationProvider {
        LunaPretranslationProvider(path: try LunaTestDatabase.make(rows + extra), lookAlikeEnabled: lookAlike)
    }

    private func translate(_ provider: LunaPretranslationProvider, _ text: String) throws -> String {
        try provider.translate(text: text, lineAlternates: [:])
    }

    // MARK: 尾部标点

    @Test func trailingPunctuationMayBeMisreadOrLost() throws {
        let p = try provider()
        #expect(try translate(p, "「相手の気持ちを、汲み取る・・・・・・") == "译1")
        #expect(try translate(p, "（そう、だったんだ…・・・・!!）") == "译2")
        #expect(try translate(p, "黄さんの一言によって、私の初カジノが始まったー") == "译3")
        #expect(try translate(p, "本当にそんな事が？*") == "译15")
    }

    @Test func recordsThatDifferOnlyInTheirEndingStayUnmatched() throws {
        let p = try provider([("「分かりました」", "明白了"), ("「分かりました……！」", "明白了……！")])
        #expect(try translate(p, "「分かりました？").hasPrefix(miss))
        // 原样对得上的不受影响
        #expect(try translate(p, "「分かりました」") == "明白了")
    }

    @Test func aStemOfFewerThanFourLettersIsNotEnough() throws {
        let p = try provider([("「はい……」", "好的……")])
        #expect(try translate(p, "「はい！").hasPrefix(miss))
    }

    // MARK: 引号读歪

    @Test func anOpeningQuoteReadAsALetterIsRestored() throws {
        let p = try provider()
        #expect(try translate(p, "1嫌ですが？」") == "译4")
        #expect(try translate(p, "嫌ですが？」") == "译4")
        #expect(try translate(p, "I！」") == "译5")
        #expect(try translate(p, "「........え？1") == "「……诶？」")
    }

    @Test func theTailOfAWrappedTurnIsNotPromotedToARecord() throws {
        let p = try provider([("「ね」", "呐")])
        #expect(try translate(p, "ね」").hasPrefix(miss))
    }

    @Test func mismatchedQuoteTypesAreRepaired() throws {
        let p = try provider()
        #expect(try translate(p, "二枚を変えた所で結果は同じだったけれど、役は『スリーカード」。") == "译6")
        #expect(try translate(p, "「「かがみ』…・・・・？」") == "译7")
    }

    // MARK: 一行里是相邻的几条记录

    @Test func oneLineMadeOfConsecutiveRecordsIsSplit() throws {
        let p = try provider()
        #expect(try translate(p, "...でも、彼も理解しているだろう。私のあの態度を見れば。") == "译8前。译8后。")
        #expect(try translate(p, "「え…・・・・・えっ、もうこんな時間なのっ！？」") == "「译9前……译9后！？」")
    }

    @Test func recordsThatAreNotNeighboursAreNotJoined() throws {
        let p = try provider()
        // 第 9 条和第 18 条隔得很远
        #expect(try translate(p, "私のあの態度を見れば。本当にそんな事が？").hasPrefix(miss))
        // 顺序反了也不算
        #expect(try translate(p, "私のあの態度を見れば。……でも、彼も理解しているだろう。").contains(miss))
    }

    // MARK: 名牌、符号、噪声

    @Test func aBracketedNameTagIsSetAside() throws {
        let p = try provider()
        #expect(try translate(p, "［畑中十前】（特にあの人との出会いは衝撃的だった...・・・）") == "译10")
        #expect(try translate(p, "）\n［畑中十前】（特にあの人との出会いは衝撃的だった...・・・）") == "译10")
        #expect(try translate(p, "【 23？】「嫌ですが？」") == "译4")
    }

    @Test func textWithoutJapaneseIsNeitherShownNorAMiss() throws {
        let p = try provider()
        #expect(try translate(p, "TLI") == "")
        #expect(try translate(p, "IiI\n\n■II") == "")
        // 台词下面带着模拟器的浮条：只留台词
        #expect(try translate(p, "「君が不安がっていたらその気持ちも観客にバレてしまうだろうから\nね」\n\n- pilinonr\n\nEDe ZQ 5I52 12") == "译17")
        // 有日文但库里没有：照旧标未命中
        #expect(try translate(p, "履歴ロード").hasPrefix(miss))
        // 库里本来就有的纯符号句照常命中
        #expect(try translate(p, "「！」") == "译5")
    }

    @Test func ellipsisLengthAloneDoesNotMakeALineAmbiguous() throws {
        let p = try provider()
        // 「……え？」和「…………え？」译文只差省略号长短，算同一句
        #expect(try translate(p, "「........…え？」") == "「……诶？」")
        #expect(try translate(p, "「…·・・・・・・・・誰ですか」") == "译14")
    }

    @Test func differentTranslationsBehindOneLooseKeyStillBlock() throws {
        let p = try provider([("「うん……」", "嗯……"), ("「うん…………」", "不……")])
        #expect(try translate(p, "「うん・・・」").hasPrefix(miss))
    }

    @Test func curlyQuotesAndWaveDashMatchTheirPlainForms() throws {
        let p = try provider()
        #expect(try translate(p, "更にどうやらここには通常とは別の\"ハイ&ロウ\"が存在しているら\nしい。") == "译13")
        #expect(try translate(p, "「...う〜ん、そうきますか」") == "译16")
    }

    // MARK: 短句错一个字（跟「形近字容错」开关走）

    @Test func oneWrongCharacterInAShortLineNeedsTheSetting() throws {
        #expect(try translate(provider(lookAlike: true), "「そう、完気が出たみたいで良かった」") == "译12")
        #expect(try translate(provider(lookAlike: true), "「そう、気が出たみたいで良かった」") == "译12")
        #expect(try translate(provider(), "「そう、完気が出たみたいで良かった」").hasPrefix(miss))
    }

    @Test func oneEditIsRefusedWhenAnotherLineIsClose() throws {
        let p = try provider([("「今日は元気が出たみたいだね」", "元气"), ("「今日は勇気が出たみたいだね」", "勇气")], lookAlike: true)
        #expect(try translate(p, "「今日は完気が出たみたいだね」").hasPrefix(miss))
    }

    @Test func oneEditNeedsTenCharacters() throws {
        let p = try provider([("「元気です」", "精神")], lookAlike: true)
        #expect(try translate(p, "「完気です」").hasPrefix(miss))
    }
}
