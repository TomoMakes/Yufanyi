import CoreGraphics
import Testing
@testable import ScreenTranslate

/// 2026-11-14 Money Parasite：一行中间有大空格时，前半句被单独又读了一遍。
@Suite struct OCRNestedDuplicateTests {
    private func block(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 90) -> OCRTextBlock {
        OCRTextBlock(text: text, boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func aBlockRepeatedInsideTheWholeLineIsDropped() {
        let result = OCRResult(text: "", detectedLanguage: nil, confidence: 1, blocks: [
            block("（......あれ？", x: 90, y: 200, width: 449),
            block("（......あれ？もしかしてこれってチャンスじゃない？）", x: 100, y: 200, width: 2058),
        ])
        #expect(result.dialogueText == "（......あれ？もしかしてこれってチャンスじゃない？）")
    }

    @Test func aSecondLineBelowIsKept() {
        let result = OCRResult(text: "", detectedLanguage: nil, confidence: 1, blocks: [
            block("「君が不安がっていたらその気持ちも観客にバレてしまうだろうから", x: 80, y: 200, width: 2540),
            block("ね」", x: 63, y: 90, width: 134),
        ])
        #expect(result.dialogueText == "「君が不安がっていたらその気持ちも観客にバレてしまうだろうから\nね」")
    }

    @Test func differentTextInsideTheSameRowIsKept() {
        // 同一行里夹着的另一段字（内容不同）不是重复
        let blocks = [
            block("「そうだね」", x: 100, y: 200, width: 500),
            block("「そうだね」と彼は言った。", x: 100, y: 200, width: 1200),
            block("別の文字", x: 300, y: 200, width: 300),
        ]
        let kept = OCRResult.withoutNestedDuplicates(blocks).map(\.text)
        #expect(kept == ["「そうだね」と彼は言った。", "別の文字"])
    }

    @Test func furiganaAboveUnpunctuatedWrappedLineIsDropped() {
        // 2026-11-18 色ドリ撫子：第一行无标点，上方小号注音「ふぶんりつ」也应过滤
        let result = OCRResult(text: "", detectedLanguage: nil, confidence: 1, blocks: [
            block("ふぶんりつ", x: 1400, y: 295, width: 220, height: 40),
            block("非番の前の日以外は部屋に泊まらないという不文律が", x: 100, y: 200, width: 1700, height: 90),
            block("あり、それに関して今まで諍いめいたものもなかった。", x: 100, y: 80, width: 1750, height: 90),
        ])
        #expect(result.dialogueText == "非番の前の日以外は部屋に泊まらないという不文律が\nあり、それに関して今まで諍いめいたものもなかった。")
    }

    @Test func sameRowDialogueContinuationAfterGapIsKept() {
        // 2026-11-20 色ドリ撫子：句中全角空格或破折号把同行右半句拆开，不能当成右侧 UI 按钮删掉
        let result = OCRResult(text: "", detectedLanguage: nil, confidence: 1, blocks: [
            block("「大丈夫よ。言ったでしょう？", x: 100, y: 200, width: 900, height: 90),
            block("喬さんは", x: 1180, y: 200, width: 320, height: 90),
            block("私に手を上げたりしないわ」", x: 120, y: 80, width: 920, height: 90),
            // 右侧不同行的小号 UI 按钮仍应丢弃
            block("AUTO", x: 1600, y: 20, width: 120, height: 40),
        ])
        #expect(result.dialogueText == "「大丈夫よ。言ったでしょう？喬さんは\n私に手を上げたりしないわ」")
    }
}
