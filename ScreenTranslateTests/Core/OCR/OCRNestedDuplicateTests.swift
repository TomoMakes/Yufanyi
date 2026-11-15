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
}
