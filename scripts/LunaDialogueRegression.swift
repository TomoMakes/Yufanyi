// Standalone regression runner. Compiles the actual production files, not copies.
// Only localization is stubbed; database fixtures live in a caller-supplied scratch directory.
import Foundation
import CoreGraphics
import CoreText
import SQLite3

nonisolated enum L10n {
    static let noTextFound = "no text", unsupportedLanguagePair = "unsupported"
    static let apiKeyInvalid = "key", autoDetectFailedMessage = "detect", translationSuperseded = "superseded"
    static let liveSourcePackMissing = "pack", liveWaitingForText = "waiting", noSelectedText = "no selection"
    static func translationFailed(_ text: String) -> String { text }
    static func ocrFailed(_ text: String) -> String { text }
}

@MainActor final class FixtureOCR: OCRProvider {
    let result: OCRResult
    init(_ result: OCRResult) { self.result = result }
    func recognize(image: CGImage) async throws -> OCRResult { result }
}
@MainActor final class FixtureFrames: LiveFrameSource {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
    func captureFrame(of region: LiveRegion) async throws -> CGImage { image }
}

@main struct LunaDialogueRegression {
    @MainActor static func main() async throws {
        let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var count = 0
        func expect(_ condition: Bool, _ label: String) {
            guard condition else { fatalError("FAIL: \(label)") }
            count += 1
            print("PASS: \(label)")
        }
        func fixture(_ filename: String, _ entries: [(String, String)]) throws -> LunaPretranslationProvider {
            let path = scratch.appendingPathComponent(filename).path
            // Never overwrite a previous fixture or the user's database.
            guard !FileManager.default.fileExists(atPath: path) else { fatalError("fixture exists: \(path)") }
            var db: OpaquePointer?
            guard sqlite3_open(path, &db) == SQLITE_OK else { fatalError("fixture open") }
            defer { sqlite3_close(db) }
            guard sqlite3_exec(db, "CREATE TABLE artificialtrans(source TEXT, machineTrans TEXT)", nil, nil, nil) == SQLITE_OK else { fatalError("schema") }
            for (source, translation) in entries {
                let json = String(data: try JSONSerialization.data(withJSONObject: ["rengong":translation]), encoding: .utf8)!
                let sql = "INSERT INTO artificialtrans VALUES ('\(source.replacingOccurrences(of: "'", with: "''"))','\(json.replacingOccurrences(of: "'", with: "''"))')"
                guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { fatalError("insert") }
            }
            return LunaPretranslationProvider(path: path)
        }
        func run(_ provider: LunaPretranslationProvider, _ text: String) async throws -> String {
            try await provider.translate(text: text, from: Locale.Language(identifier:"ja"), to: Locale.Language(identifier:"zh-Hans"))
        }
        let a = "「今日は図書館へ行って、昨日見つけた古い本について詳しく調べてみようと思っています。」"
        let b = "「それなら私も一緒に行きます。まだ誰も知らない秘密を二人で探してみましょう。」"
        let c = "私は窓を開けた。冷たい風が部屋の中へ静かに流れ込んできた。"
        let unknown = "「この台詞にはまだ翻訳が登録されていません。」"
        let p = try fixture("basic.sqlite", [(a,"译文甲"),(b,"译文乙"),(c,"完整旁白"),("短い台詞。","短句"),("ＡＢＣ１２３。","规范化")])
        expect(try await run(p,a) == "译文甲", "single exact")
        expect(try await run(p,a+"\n\n"+b) == "译文甲\n\n译文乙", "two spatial paragraphs")
        expect(try await run(p,a+"\n"+b) == "译文甲\n\n译文乙", "two dialogue blocks without blank line")
        expect(try await run(p,a+b) == "译文甲\n\n译文乙", "adjacent closed quotations")
        expect(try await run(p,"ヒタキ\n"+a+"\nツグミ\n"+b) == "译文甲\n\n译文乙", "separate speaker labels")
        expect(try await run(p,"ヒタキ"+a+"ツグミ"+b) == "译文甲\n\n译文乙", "same-row named dialogue blocks")
        expect(try await run(p,"未登録の文章\n\n"+a) == "［预翻译未命中］\n未登録の文章\n\n译文甲", "speaker stripping cannot discard a different paragraph")
        let wrapped = a.replacingOccurrences(of:"昨日",with:"昨\n日").replacingOccurrences(of:"詳しく",with:"詳し\nく")
        expect(try await run(p,wrapped+"\n\n"+b) == "译文甲\n\n译文乙", "soft wraps inside full dialogue")
        let mixed = try await run(p,a+"\n\n"+unknown+"\n\n"+b)
        expect(mixed == "译文甲\n\n［预翻译未命中］\n"+unknown+"\n\n译文乙", "miss between independent hits")
        expect(try await run(p,c.replacingOccurrences(of:"。冷",with:"。\n冷")) == "完整旁白", "multi-sentence paragraph kept intact")
        expect(try await run(p,"ABC123。") == "规范化", "existing compatibility normalization")
        let typo = a.replacingOccurrences(of:"図書館",with:"図書官")
        expect(try await run(p,typo+"\n\n"+b) == "译文甲\n\n译文乙", "one OCR error plus independent exact hit")
        expect(try await run(p,"短い台調。") .hasPrefix("［预翻译未命中］"), "short fuzzy rejected")
        let bad = a.replacingOccurrences(of:"図書館",with:"映画室").replacingOccurrences(of:"昨日",with:"明日").replacingOccurrences(of:"古い本",with:"新しい絵")
        expect(try await run(p,bad).hasPrefix("［预翻译未命中］"), "below-threshold rejected")
        let rival = a.replacingOccurrences(of:"図書館",with:"図書室")
        let ambiguous = try fixture("ambiguous.sqlite", [(a,"译文甲"),(rival,"不同译文")])
        expect(try await run(ambiguous,typo).hasPrefix("［预翻译未命中］"), "ambiguous fuzzy rejected")
        expect(try await run(ambiguous,a) == "译文甲", "exact outranks similar row")
        let conflicts = try fixture("conflicts.sqlite", [(a,"译文甲"),(a,"相互冲突的译文")])
        expect(try await run(conflicts,a).hasPrefix("［预翻译未命中］"), "conflicting exact database rows rejected")
        expect(try await run(p,a+unknown) == "译文甲\n\n［预翻译未命中］\n"+unknown, "containment cannot swallow unknown dialogue")
        expect(try await run(p,"\n\n  \n").isEmpty, "blank input")
        let splitA = a.index(a.startIndex,offsetBy:20)
        let blocks = [OCRTextBlock(text:String(a[..<splitA]),boundingBox:CGRect(x:10,y:200,width:700,height:20)),
                      OCRTextBlock(text:String(a[splitA...]),boundingBox:CGRect(x:10,y:173,width:700,height:20)),
                      OCRTextBlock(text:unknown,boundingBox:CGRect(x:10,y:110,width:700,height:20)),
                      OCRTextBlock(text:b,boundingBox:CGRect(x:10,y:50,width:700,height:20))]
        let result = OCRResult(text:blocks.map(\.text).joined(separator:"\n"),detectedLanguage:nil,confidence:1,blocks:blocks)
        expect(result.dialogueText.components(separatedBy:"\n\n").count == 3, "OCR geometry separates paragraphs, retains line wrap")
        let spacedWrap = OCRResult(text:"",detectedLanguage:nil,confidence:1,blocks:[
            OCRTextBlock(text:String(typo.prefix(20)),boundingBox:CGRect(x:10,y:200,width:700,height:20)),
            OCRTextBlock(text:String(typo.dropFirst(20)),boundingBox:CGRect(x:10,y:130,width:700,height:20))])
        let spacedTranslation = try await run(p,spacedWrap.dialogueText)
        expect(!spacedWrap.dialogueText.contains("\n\n") && spacedTranslation == "译文甲", "open quotation survives large OCR line gap and typo")
        let nameBlock = OCRResult(text:"",detectedLanguage:nil,confidence:1,blocks:[
            OCRTextBlock(text:"ヒタキ",boundingBox:CGRect(x:10,y:220,width:80,height:20)),blocks[0],blocks[1]])
        expect(try await run(p,nameBlock.dialogueText) == "译文甲", "separate name box stays with dialogue")
        var stable = LiveTextStabilizer()
        expect(stable.ingest(result.dialogueText,preservingLineBreaks:true) == nil, "Luna waits for stable OCR")
        expect(stable.ingest(result.dialogueText,preservingLineBreaks:true) == .show(result.dialogueText), "Luna stabilizer preserves boundaries")
        var normal = LiveTextStabilizer()
        _ = normal.ingest("Hello\nworld")
        expect(normal.ingest(" Hello  world ") == .show("Hello world"), "other providers keep previous normalization")

        let context = CGContext(data:nil,width:1024,height:360,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:1024,height:360))
        let image = context.makeImage()!
        let region = LiveRegion(rect:CGRect(x:23,y:47,width:1024,height:360),displayID:1,scale:1)
        let session = LiveTranslationSession(dependencies:.init(frameSource:FixtureFrames(image),ocr:FixtureOCR(result),translator:p,isTranslatorBusy:{false},interval:.milliseconds(10)),region:{region},languages:{(Locale.Language(identifier:"ja"),Locale.Language(identifier:"zh-Hans"))},preprocess:{true})
        session.start()
        for _ in 0..<100 where session.translationCount == 0 { try await Task.sleep(for:.milliseconds(10)) }
        expect(session.display == .subtitle(mixed), "live pipeline: OCR geometry → stabilization → SQLite → partial-hit display")
        session.stop(.user)
        expect(region.rect == CGRect(x:23,y:47,width:1024,height:360), "capture region unchanged")

        if CommandLine.arguments.count > 2 {
            let realPath = CommandLine.arguments[2]
            var db: OpaquePointer?
            guard sqlite3_open_v2(realPath,&db,SQLITE_OPEN_READONLY,nil) == SQLITE_OK else { fatalError("readonly database") }
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db,"SELECT source,machineTrans FROM artificialtrans WHERE length(source) > 35 AND source LIKE '「%' LIMIT 3",-1,&stmt,nil)
            defer { sqlite3_finalize(stmt) }
            var samples:[(String,String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let source = String(cString:sqlite3_column_text(stmt,0))
                let raw = String(cString:sqlite3_column_text(stmt,1))
                let dict = try JSONSerialization.jsonObject(with:raw.data(using:.utf8)!) as! [String:String]
                samples.append((source,dict["rengong"]!))
            }
            let real = LunaPretranslationProvider(path:realPath)
            let input = samples.map { source,_ in
                let i = source.index(source.startIndex,offsetBy:source.count/2)
                return "ヒタキ\n"+source[..<i]+"\n"+source[i...]
            }.joined(separator:"\n\n")
            expect(try await run(real,input) == samples.map(\.1).joined(separator:"\n\n"), "user database: three wrapped dialogues with names independently match")
            let sampleTypo = samples[0].0.replacingOccurrences(of:"正式",with:"正弍")
            expect(try await run(real,sampleTypo+"\n\n"+samples[1].0) == samples[0].1+"\n\n"+samples[1].1, "user database: conservative OCR typo recovery plus second exact paragraph")
            let example = "INPUT\n"+input+"\n\nOUTPUT\n"+(try await run(real,input))
            try example.write(to:scratch.appendingPathComponent("real-database-example.txt"),atomically:true,encoding:.utf8)

            // Real Vision OCR on a synthetic image, without moving or capturing any user window.
            let font = CTFontCreateWithName("HiraginoSans-W3" as CFString,26,nil)
            var y:CGFloat = 305
            for (source,_) in samples.prefix(2) {
                let middle = source.index(source.startIndex,offsetBy:source.count/2)
                for line in [String(source[..<middle]),String(source[middle...])] {
                    let attrs:[NSAttributedString.Key:Any] = [.init(kCTFontAttributeName as String):font,.init(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)]
                    let ctline = CTLineCreateWithAttributedString(NSAttributedString(string:line,attributes:attrs))
                    context.textPosition = CGPoint(x:30,y:y); CTLineDraw(ctline,context); y -= 36
                }
                y -= 45
            }
            let recognized = try await VisionOCRProvider().recognize(image:context.makeImage()!)
            print("VISION OCR:\n\(recognized.dialogueText)")
            expect(try await run(real,recognized.dialogueText) == samples.prefix(2).map(\.1).joined(separator:"\n\n"), "Vision image OCR → two real database translations")
        }
        // Round 2: additive checks; collect all failures before asserting the group.
        var round2Failures = 0
        func check2(_ ok: Bool, _ label: String) {
            print("ROUND2 \(ok ? "PASS" : "FAIL"): \(label)")
            if !ok { round2Failures += 1 }
        }
        let punctuation = try fixture("round2-punctuation.sqlite", [("「……そうか」","省略"),("「――待って」","破折"),("「......」","A"),("「...」","B"),("「......嘘」","C"),("「...嘘」","D"),("『そうか』","双引号")])
        for input in ["「・・・・・・そうか」","「・・・・・・・そうか」","「⋯そうか」","「•・・・・・そうか」"] {
            check2(try await run(punctuation,input) == "省略", "ellipsis " + input)
        }
        for input in ["「ーー待って」","「一一待って」","「一ー待って」"] {
            check2(try await run(punctuation,input) == "破折", "dash " + input)
        }
        check2(try await run(punctuation,"「......」") == "A", "strict six dots")
        check2(try await run(punctuation,"「...」") == "B", "strict three dots")
        check2(try await run(punctuation,"「・・・・嘘」").hasPrefix("［预翻译未命中］"), "loose collision rejected")
        check2(try await run(punctuation,"「そうか」").hasPrefix("［预翻译未命中］"), "quote types remain distinct")
        let mono = "（どうしよう、もう間に合わない……）"
        let monologues = try fixture("round2-mono.sqlite", [(mono,"独白")])
        for input in ["ツグミ\n"+mono,"ツグミ"+mono,"ツグミ"+mono.precomposedStringWithCompatibilityMapping] {
            check2(try await run(monologues,input) == "独白", "named monologue " + input)
        }
        let parenthesis = "ユリナ（母親）は入院中だ。"
        let embedded = "テラくんの出した答えは『元部員Ｄ』で矛盾がわかる証拠は『オカルト雑誌』。"
        let safety = try fixture("round2-safety.sqlite", [(parenthesis,"整句括号"),("（母親）","短括号"),("母親","短词"),(embedded,"整句引号"),("『元部員Ｄ』","短语一"),("『オカルト雑誌』","短语二")])
        for input in [parenthesis,"ツグミ\n"+parenthesis,"ユリナ（母\n親）は入院中だ。"] {
            let actual = try await run(safety,input)
            check2(actual == "整句括号" || actual.hasPrefix("［预翻译未命中］") && !actual.contains("短括号") && !actual.contains("短词"), "embedded parentheses " + input)
        }
        for input in ["ツグミ\n"+embedded,embedded.replacingOccurrences(of:"オカルト",with:"オカル卜")] {
            let actual = try await run(safety,input)
            check2(actual == "整句引号" || actual.hasPrefix("［预翻译未命中］") && !actual.contains("短语一") && !actual.contains("短语二"), "embedded quotations " + input)
        }
        let truncated = try fixture("round2-truncated.sqlite", [("…………","省略短句"),("「……」","闭合省略")])
        for input in ["「……","（……","「………"] {
            check2(try await run(truncated,input).hasPrefix("［预翻译未命中］"), "loose cannot recover unclosed turn " + input)
        }
        let quoteNarrative = "『じゃあ、またね』と言って、友達のところに駆けていく。"
        let leading = try fixture("round2-leading.sqlite", [(quoteNarrative,"完整引语旁白"),("『じゃあ、またね』","独立引语")])
        for input in ["ヒタキ\n"+quoteNarrative,"ヒタキ"+quoteNarrative] {
            check2(try await run(leading,input) == "完整引语旁白", "named quotation-leading narrative stays whole " + input)
        }
        expect(round2Failures == 0, "round 2 additive checks")

        // Round 3: additive fixtures, reported individually before asserting the group.
        var round3Failures = 0
        func check3(_ ok: Bool, _ label: String) {
            print("ROUND3 \(ok ? "PASS" : "FAIL"): \(label)")
            if !ok { round3Failures += 1 }
        }
        let shortLong = "「……今日は図書館へ行って古い本について詳しく調べます……」"
        let twoLong = "「…………今日は図書館へ行って古い本について詳しく調べます。そして昨日見つけた秘密を友達と一緒に考えてみたいと思っています…………」"
        let r3p = try fixture("round3.sqlite", [(shortLong,"严格长度一错"),(twoLong,"严格长度两错"),
            ("「おはよう」","早上好"),("「こんにちは」","你好"),
            ("『神秘派過激グループ』","神秘派激进团体"),("「ええと……リンゴ先生……？」","苹果老师"),
            ("「リョクハの居場所を奪って、あいつが苦しみながら死んでくれたら、俺はそれだけでいーんだよ」","漏尾引号"),
            ("「僕はね、あの不思議な本───『稀モノ』と向かい合う彼等を見ているのが大好きなんだよ」","稀物整句")])
        check3(try await run(r3p,shortLong.replacingOccurrences(of:"図書館",with:"図書官")) == "严格长度一错", "1 strict length one typo")
        check3(try await run(r3p,twoLong.replacingOccurrences(of:"図書館",with:"図書官").replacingOccurrences(of:"友達",with:"友逹")) == "严格长度两错", "1 strict length two typos")
        for (name,sep) in [("お母さん","\n"),("女の子"," "),("生徒１","\n"),("シーマ",""),("テラくん","\n"),("あかり","　")] {
            check3(try await run(r3p,name+sep+"「おはよう」") == "早上好", "2 name " + name + " separator=" + sep.debugDescription)
        }
        check3(try await run(r3p,"『神秘派過激グループ』\n「ええと……リンゴ先生……？」") == "神秘派激进团体\n\n苹果老师", "2 quoted phrase must not disappear")
        for prefix in ["。","、","！","？","!","?","（母親）","(母親)","『名前』","「名前」"] {
            let actual = try await run(r3p,prefix+"\n「おはよう」")
            check3(actual.contains(prefix) && actual.contains("［预翻译未命中］"), "2 forbidden name punctuation " + prefix)
        }
        check3(try await run(r3p,"あかり「おはよう」").hasPrefix("［预翻译未命中］"), "2 attached hiragana rejected")
        check3(try await run(safety,embedded) == "整句引号", "2 6903 full narrative")
        check3(try await run(safety,"花子\n"+embedded).hasPrefix("［预翻译未命中］"), "2 6903 named narrative not stripped")
        check3(try await run(safety,parenthesis) == "整句括号", "2 parenthetical narrative intact")
        for sep in [" ","　","\t"] {
            check3(try await run(r3p,"ヒタキ「おはよう」"+sep+"ツグミ「こんにちは」") == "早上好\n\n你好", "3 spaced turns " + sep.debugDescription)
        }
        check3(try await run(r3p,"ヒタキ\n「リョクハの居場所を奪って、あいつが苦しみながら死んでくれたら、俺はそれだけでいーんだよ") == "漏尾引号", "4 named missing closing quote")
        check3(try await run(truncated,"ヒタキ\n「………").hasPrefix("［预翻译未命中］"), "4 named open loose match forbidden")
        let openStrict = try fixture("round3-open-strict.sqlite", [("「閉じない台詞","未闭合原记录")])
        check3(try await run(openStrict,"ヒタキ\n「閉じない台詞") == "未闭合原记录", "4 strict open record with name")
        let r3blocks = [
            OCRTextBlock(text:"「僕はね、あの不思議な本",boundingBox:CGRect(x:20,y:56,width:390,height:40)),
            OCRTextBlock(text:"『稀モノ』と",boundingBox:CGRect(x:523,y:62,width:186,height:35)),
            OCRTextBlock(text:"向かい合う彼等を見ているのが大好きなんだよ」",boundingBox:CGRect(x:36,y:10,width:725,height:38))]
        let r3ocr = OCRResult(text:"",detectedLanguage:nil,confidence:1,blocks:r3blocks).dialogueText
        check3(!r3ocr.contains("\n\n"), "6 nested OCR geometry no paragraph")
        check3(try await run(r3p,r3ocr) == "稀物整句", "6 nested OCR geometry translates")
        expect(round3Failures == 0, "round 3 additive checks")
        // Round 3b: preserve first-line content and independent OCR turns.
        var patchFailures = 0
        func checkPatch(_ ok: Bool, _ label: String) {
            print("PATCH \(ok ? "PASS" : "FAIL"): \(label)")
            if !ok { patchFailures += 1 }
        }
        let patch0 = try fixture("patch0.sqlite", [("警戒なんてしてない","才没有在警戒呢。"),("「……何かあったの？」","「……发生什么事了吗？」")])
        let result0 = try await run(patch0,"警戒なんてしてない\n「……何かあったの？」")
        checkPatch(result0 == "才没有在警戒呢。\n\n「……发生什么事了吗？」" || (result0.contains("［预翻译未命中］") && result0.contains("警戒なんてしてない")), "firstline A 4615")
        let patch1 = try fixture("patch1.sqlite", [("心配しないで","别担心"),("（どうしよう……こんな時に言うべきことではないかしら）","（怎么办……这种时候是不是不该说这些）")])
        let result1 = try await run(patch1,"心配しないで\n（どうしよう……こんな時に言うべきことではないかしら）")
        checkPatch(result1 == "别担心\n\n（怎么办……这种时候是不是不该说这些）" || (result1.contains("［预翻译未命中］") && result1.contains("心配しないで")), "firstline A 47028")
        let patch2 = try fixture("patch2.sqlite", [("宇宙人のメッセージ","外星人的信息"),("「この絵は――シーマくんの画風だと思います。個性が爆発してますね……」","「这幅画――我觉得是希真君的画风。个性爆棚呢……」")])
        let result2 = try await run(patch2,"宇宙人のメッセージ\n「この絵は――シーマくんの画風だと思います。個性が爆発してますね……」")
        checkPatch(result2 == "外星人的信息\n\n「这幅画――我觉得是希真君的画风。个性爆棚呢……」" || (result2.contains("［预翻译未命中］") && result2.contains("宇宙人のメッセージ")), "firstline B 26635")
        let patch3 = try fixture("patch3.sqlite", [("メガネかけるんですね","你戴眼镜啊"),("「いえ……いつもと雰囲気が違うから、ちょっとびっくりして」","「不……因为和平时氛围不一样，有点惊讶」")])
        let result3 = try await run(patch3,"メガネかけるんですね\n「いえ……いつもと雰囲気が違うから、ちょっとびっくりして」")
        checkPatch(result3 == "你戴眼镜啊\n\n「不……因为和平时氛围不一样，有点惊讶」" || (result3.contains("［预翻译未命中］") && result3.contains("メガネかけるんですね")), "firstline B 22321")
        let patchShort = try fixture("patch-short.sqlite", [("あかり","短首行"),("「おはよう」","早上好"),("あ――あ","宽松首行")])
        for prefix in ["あかり","あーーあ"] {
            let actual = try await run(patchShort,prefix+"\n「おはよう」")
            checkPatch(actual.contains("［预翻译未命中］") && actual.contains(prefix), "short database prefix " + prefix)
        }
        for prefix in ["雨が降っている","つづきから"] {
            let actual = try await run(r3p,prefix+"\n「おはよう」")
            checkPatch(actual.contains("［预翻译未命中］") && actual.contains(prefix), "unknown prefix " + prefix)
        }
        for name in ["お母さん","女の子","生徒１","テラくん","あかり"] {
            for sep in ["\n"," "] {
                checkPatch(try await run(r3p,name+sep+"「おはよう」") == "早上好", "retained name " + name + sep.debugDescription)
            }
        }
        // Reusing r3p after patchShort also catches accidental global lookup state.
        checkPatch(try await run(r3p,"あかり\n「おはよう」") == "早上好", "provider isolation")
        let patchBlocks = [OCRTextBlock(text:String(a.dropLast()),boundingBox:CGRect(x:20,y:100,width:600,height:20)),
                           OCRTextBlock(text:b,boundingBox:CGRect(x:20,y:50,width:600,height:20))]
        let patchOCR = OCRResult(text:"",detectedLanguage:nil,confidence:1,blocks:patchBlocks).dialogueText
        checkPatch(patchOCR.contains("\n\n"), "OCR new opening separates")
        checkPatch(try await run(p,patchOCR) == "译文甲\n\n译文乙", "OCR second turn translates")
        let nestedActual = try await run(r3p,r3ocr)
        checkPatch(!r3ocr.contains("\n\n") && nestedActual == "稀物整句", "OCR nested retained 30442")
        for prefix in ["公的誤理由","ホワイトボ誤ド","キャスト誤客"] {
            let actual = try await run(r3p,prefix+"\n「おはよう」")
            checkPatch(actual.contains("［预翻译未命中］") && actual.contains(prefix), "unknown prefix lost hiragana " + prefix)
        }
        expect(patchFailures == 0, "round 3b additive checks")
        print("ALL \(count) CHECKS PASSED")
    }
}
