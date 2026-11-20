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

    // MARK: 2026-11-18 色ドリ撫子 反馈

    @Test func leadingDashOnShortNarrationMayBeDroppedOrReadAsHyphen() throws {
        let p = try provider([
            ("───彼だからだ。", "───是因为他。"),
            ("───あれから一年。", "───那之后过了一年。"),
            ("───『空舟櫂』。", "───『空舟棹』。"),
        ])
        #expect(try translate(p, "-彼だからだ。") == "───是因为他。")
        #expect(try translate(p, "あれから一年。") == "───那之后过了一年。")
        #expect(try translate(p, "『空舟櫂』。") == "───『空舟棹』。")
    }

    @Test func leadingDashBlocksWhenCompetingPlainRecordExistsOrTooShort() throws {
        let p = try provider([
            ("───彼だからだ。", "───是因为他。"),
            ("彼だからだ。", "因为是他。"),
            ("───はい。", "───好的。"),
        ])
        // 不带破折号的本句在库里译文不同：直接按本句走，读出 - 时因冲突不猜
        #expect(try translate(p, "彼だからだ。") == "因为是他。")
        #expect(try translate(p, "-彼だからだ。").hasPrefix(miss))
        // 少于 4 字的无书名号短句不放行
        #expect(try translate(p, "はい。").hasPrefix(miss))
    }

    @Test func shortLineUsesVisionAlternateFromFiveLetters() throws {
        let p = try provider([
            ("「君を欺いた女だ」", "「她可是骗了你的女人」"),
            ("「君を待つ」", "「等你」"),
        ])
        let hit = try p.translate(
            text: "「君をいた女だ」",
            lineAlternates: ["「君をいた女だ」": ["「君を欺いた女だ」"]]
        )
        #expect(hit == "「她可是骗了你的女人」")
        // 少于 5 字不走候选替换
        let tooShort = try p.translate(
            text: "「君を待」",
            lineAlternates: ["「君を待」": ["「君を待つ」"]]
        )
        #expect(tooShort.hasPrefix(miss))
    }

    @Test func hiraganaFuriganaPrefixUpToEightCharsStillTranslatesBody() throws {
        let body = "非番の前の日以外は部屋に泊まらないという不文律があり、それに関して今まで諍いめいたものもなかった。"
        let trans = "除了休息日前一天，他从不留我在房间过夜——这是不成文的规矩，至今也没为此闹过什么别扭。"
        let p = try provider([(body, trans)])
        let output = try translate(p, "ふぶんりつ\n非番の前の日以外は部屋に泊まらないという不文律が\nあり、それに関して今まで諍いめいたものもなかった。")
        #expect(output == "［原文前缀］\nふぶんりつ\n\n" + trans)
    }

    @Test func threeLetterNarrationWithDashAndPeriodReadAsO() throws {
        let p = try provider([
            ("すると───。", "于是───。"),
            ("けれど。", "可是。"),
            ("けれど───。", "可是───。"),
        ])
        #expect(try translate(p, "すると一 o") == "于是───。")
        // 有竞争记录（けれど。 vs けれど───。）时仍拦截
        #expect(try translate(p, "けれど一 o").hasPrefix(miss))
        // 带引号的 3 字短句不走这条
        let quoted = try provider([("「すると───。」", "「于是───。」")])
        #expect(try translate(quoted, "「すると一 o").hasPrefix(miss))
    }

    @Test func shortQuotedLineWithGarbledLeadingEllipsisAndDash() throws {
        let p = try provider([
            ("「……───断る」", "「……───不要」"),
            ("「断る」", "「我拒绝」"),
            ("「……───でも」", "「……───可是」"),
            ("「……でも」", "「……可是」"),
            ("「でも」", "「但是」"),
        ])
        // 明确带 3 个以上省略号/破折号前缀的 2 字短句能准确命中，不被无符号原句拦掉
        #expect(try translate(p, "…・・・」断る」") == "「……───不要」")
        #expect(try translate(p, "・…・・・・・」ーでも」") == "「……───可是」")
        // 无符号原句依然走各自精确命中
        #expect(try translate(p, "「断る」") == "「我拒绝」")
        #expect(try translate(p, "「でも」") == "「但是」")
        // 只有 1 个噪声点时不放宽，避免把「断る」误配成「……───断る」
        #expect(try translate(p, "「・断る」").hasPrefix(miss))
        // 1 字超短句或未闭合引号仍不放行
        let unsafe = try provider([("「……え」", "「……诶」"), ("「君……───」", "「你……───」")])
        #expect(try translate(unsafe, "・・え」 ・」").hasPrefix(miss))
        #expect(try translate(unsafe, "「- 「君・......").hasPrefix(miss))
    }

    // MARK: 2026-11-20 色ドリ撫子（11-19 晚反馈）+ Money Parasite 遗留项

    @Test func ellipsisSokuonReadAsBulletOrTsuMatchesSafely() throws {
        let p = try provider([
            ("「……な、何ですか、いきなり……っ」", "「……什、什么啊，突然说这个……」"),
            ("「あ……赤ちゃ……っ、う……っ、あ……ああ……───っ！」", "「啊……宝宝……唔……啊……啊啊……───！」"),
            ("「いや、笑わずには……はぁ、ごめん……っ、うん、素晴らしい画策だと思うよ、お見それした……っ」", "「不，我忍不住笑了……哈，抱歉……嗯，我觉得是很棒的计划，佩服……」"),
            // 竞争反例：有不同译文的无 っ 原句时必须拦截
            ("「じいや……」", "「管家……」"),
            ("「じいや……っ」", "「管家……！」"),
        ])
        #expect(try translate(p, "「・・・・・・・な、何ですか、いきなり・・・・・・•」") == "「……什、什么啊，突然说这个……」")
        #expect(try translate(p, "「あ・・・・・・赤ちゃ・・・・・・・•、う・・・・・・・•、\nあ・・・・・ああ・・・・・・ーっ！」") == "「啊……宝宝……唔……啊……啊啊……───！」")
        #expect(try translate(p, "「いや、笑わずには…・・・・・はあ、ごめん…・・・・・•、うん、\n素晴らしい画策だと思うよ、お見それした・・・・・・つ」") == "「不，我忍不住笑了……哈，抱歉……嗯，我觉得是很棒的计划，佩服……」")
        // 竞争短句各走精确命中，不串句
        #expect(try translate(p, "「じいや……」") == "「管家……」")
    }

    @Test func leadingSymbolAllowsMisreadOpeningQuoteAndPostEllipsisSingleDash() throws {
        let p = try provider([
            ("「……───警察は駄目なんだ」", "「……——警察不行」"),
            ("「なら……───」", "「那就……───」"),
            ("「この国……───」", "「这个国家……───」"),
            // 反例：有竞争的无破折号记录且译文不同时拦住
            ("「あの人……───」", "「那个人……───」"),
            ("「あの人……」", "「那个人……」"),
        ])
        #expect(try translate(p, "！....・・」警察は駄目なんだ」") == "「……——警察不行」")
        #expect(try translate(p, "「なら・・....-」") == "「那就……───」")
        #expect(try translate(p, "「この国.......」") == "「这个国家……───」")
        // 两个译文只在省略号/破折号长度不同时 foldedTranslation 一致可命中；若译文实质不同则拦截
        let conflict = try provider([
            ("「あの人……───」", "「那个人怎么了」"),
            ("「あの人……」", "「那个人吗」"),
        ])
        #expect(try translate(conflict, "「あの人......」") == "「那个人吗」")
    }

    @Test func lookAlikeCombinesWithDroppedQuoteOrDash() throws {
        let p = try provider([
            ("「次は“ハイ&ロウ”で勝負しようか」", "「下一局玩“比大小”吧」"),
            ("「最後は……───ぼろ屑に成り果てて死ぬ」", "「最后……───沦为破布般死去」"),
            ("「……澄蓮さん……！！」", "「……澄莲小姐……！！」"),
        ], lookAlike: true)
        // Money Parasite #53/#54：ウ→ヴ 同时丢了一个弯引号
        #expect(try translate(p, "「次はハイ&ロヴ”で勝負しようか」") == "「下一局玩“比大小”吧」")
        // 色ドリ撫子 #21：屑→層 同时丢破折号
        #expect(try translate(p, "「最後は........ ぼろ層に成り果てて死ぬ」") == "「最后……───沦为破布般死去」")
        // 色ドリ撫子 #28：澄→登
        #expect(try translate(p, "「・・・・・・登蓮さん・・・・・・！！」") == "「……澄莲小姐……！！」")
    }

    @Test func autoShortcutAcceptsDeterministicRuleHitsAndRejectsHalfTypedLines() throws {
        let p = try provider([
            ("「……——大丈夫、悪人ではないわ」", "「……——放心吧，她不是坏人」"),
            ("「君を欺いた女だ」", "「她可是骗了你的女人」"),
            ("彼は走った。", "他跑了。"),
        ])
        // 数据库尚未加载时不走单帧放行
        #expect(!p.isCompleteExactHit("「……——大丈夫、悪人ではないわ」"))
        // 任意一次正常查询后加载完成
        _ = try translate(p, "「……——大丈夫、悪人ではないわ」")

        // AUTO 下常见读法：……—— 被读成一串点，甚至漏掉开引号
        #expect(p.isCompleteExactHit("「………………大丈夫、悪人ではないわ」"))
        #expect(p.isCompleteExactHit("「・・.....大丈夫、悪人ではないわ」"))
        #expect(p.isCompleteExactHit("・・・・・・大丈夫、悪人ではないわ」"))
        // 含短说话人前缀、或借助候选读法命中
        #expect(p.isCompleteExactHit("ツグミ\n「……——大丈夫、悪人ではないわ」"))
        #expect(p.isCompleteExactHit("「君をいた女だ」", lineAlternates: ["「君をいた女だ」": ["「君を欺いた女だ」"]]))
        // 尾部误读（不含省略号半截）也可放行，半截打字或无匹配必须拦截
        #expect(p.isCompleteExactHit("（そう、だったんだ…・・・・!!）"))
        #expect(!p.isCompleteExactHit("「……——大丈夫、悪人"))
        #expect(!p.isCompleteExactHit("「え……"))
        #expect(!p.isCompleteExactHit("ね」"))
        #expect(!p.isCompleteExactHit("彼は走った…"))
    }

    @Test func leadingDashReadAsKanjiOneLongNamePrefixOrDroppedOpeningRunStillMatches() throws {
        let p = try provider([
            ("「……───私が夫を愛しているか？」", "「……───问我爱不爱丈夫？」"),
            ("「……一日中」", "「……一整天」"),
        ])
        // 实机 3 种读法：破折号读成「一」、带 5 字无平假名说话人、整段「……───丢掉
        #expect(try translate(p, "…・」一私が夫を愛しているか？」") == "「……───问我爱不爱丈夫？」")
        #expect(try translate(p, "四木沼薔子\n「………………-私が夫を愛しているか？」") == "［原文前缀］\n四木沼薔子\n\n「……───问我爱不爱丈夫？」")
        #expect(try translate(p, "私が夫を愛しているか？」") == "「……───问我爱不爱丈夫？」")
        #expect(p.isCompleteExactHit("…・」一私が夫を愛しているか？」"))
        #expect(p.isCompleteExactHit("四木沼薔子\n「………………-私が夫を愛しているか？」"))
        #expect(p.isCompleteExactHit("私が夫を愛しているか？」"))
        // 正文原本就以「一」开头时不被误切
        #expect(try translate(p, "「……一日中」") == "「……一整天」")
        // 有竞争的无符号原句时，丢掉整个开头的写法必须拦住
        let conflict = try provider([
            ("「……───私が夫を愛しているか？」", "「……───问我爱不爱丈夫？」"),
            ("「私が夫を愛しているか？」", "「我是否爱着丈夫？」"),
        ])
        #expect(try translate(conflict, "私が夫を愛しているか？」") == "「我是否爱着丈夫？」")
    }

    // MARK: 2026-11-20 sins of KALEIDO 反馈

    @Test func angleBracketsAndMismatchedParensOrKuStillMatch() throws {
        let p = try provider([
            ("『へぇ......すごい。いっぱいあるね。〈お金をたくさんかせぎたい〉、〈背が高くなりたい〉、〈えらくなりたい〉、〈美術館の人になりたい〉......』", "『嘿……好厉害。〈想赚很多钱〉……』"),
            ("『〈はやく大人になりたい〉〈お父さんみたいに頭がいい人になりたい〉、〈お母さんみたいにキレイになりたい〉......』", "『〈想快点长大〉……』"),
            ("「『あなたの《困った》を即解決』......詐欺でも始める気か?」", "「『你的《烦恼》立即解决』……你是打算开始搞诈骗吗?」"),
        ])
        #expect(try translate(p, "『へぇ・・・・・すごい。いっぱいあるね。\n<お金をたくさんかせぎたい）、<背が高くなりたい）、\nくえらくなりたい）、く美術館の人になりたい＞・・・」") == "『嘿……好厉害。〈想赚很多钱〉……』")
        #expect(try translate(p, "『くはやく大人になりたい>\n＜お父さんみたいに頭がいい人になりたい）、\n＜お母さんみたいにキレイになりたい＞…・・』") == "『〈想快点长大〉……』")
        #expect(try translate(p, "「『あなたの＜困った）を即解決』\n…・・・・詐欺でも始める気か？」") == "「『你的《烦恼》立即解决』……你是打算开始搞诈骗吗?」")
    }

    @Test func smallKanaLeadingOneDateAndDoublePrimeQuotesMatchSafely() throws {
        let p = try provider([
            ("「くっ......はぁはぁ......っ。......!?」", "「唔……哈啊哈啊……呼……!?」"),
            ("——9月28日", "——9月28日"),
            ("「〝異端者―グリムナル―〟による犯罪は」", "「\"异端者-格林姆纳尔-\"造成的犯罪」"),
            ("「君たちは唯一政府に存在を許された〝異端者―グリムナル―〟......だろう?組織の名は、ええっと」", "「你们是唯一被政府允许存在的\"异端者-格林姆纳尔-\"……对吧?组织的名字是，呃……」"),
            ("「他の〝異端者―グリムナル―〟のことは化け物扱いしてるクセに。都合いいよなぁ?」", "「明明把其他\"异端者-格林姆纳尔-\"的家伙当怪物看待。真够双标的，对吧?」"),
            ("「一日中」", "「一整天」"),
        ])
        #expect(try translate(p, "「くっ・・・・・・はあはぁ…・つ。…・・！？」") == "「唔……哈啊哈啊……呼……!?」")
        #expect(try translate(p, "一9月28日") == "——9月28日")
        #expect(try translate(p, "「異端者ーグリムナルー、による犯罪は」") == "「\"异端者-格林姆纳尔-\"造成的犯罪」")
        #expect(try translate(p, "「君たちは唯一政府に存在を許された\n\"異端者ーグリムナルーミ..・・だろう？\n組織の名は、ええっと」") == "「你们是唯一被政府允许存在的\"异端者-格林姆纳尔-\"……对吧?组织的名字是，呃……」")
        #expect(try translate(p, "「他の異端者ーグリムナルー、のことは化け物扱い\nしてるクセに。都合いいよなあ？」") == "「明明把其他\"异端者-格林姆纳尔-\"的家伙当怪物看待。真够双标的，对吧?」")

        // 大小假名存在不同译文时必须拦截；正常「一日中」不被剥掉「一」
        let conflict = try provider([
            ("「はぁはぁ……っ」", "「哈啊哈啊……」"),
            ("「はあはぁ……っ」", "「是啊哈啊……」"),
        ])
        #expect(try translate(conflict, "「はあはあ……っ」").hasPrefix(miss))
        #expect(try translate(p, "「一日中」") == "「一整天」")
    }
}
