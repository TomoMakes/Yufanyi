import Foundation
import CoreGraphics
import CoreText
import SQLite3
nonisolated enum L10n {
 static let noTextFound="no text", unsupportedLanguagePair="unsupported", apiKeyInvalid="key", autoDetectFailedMessage="detect", translationSuperseded="superseded"
 static func translationFailed(_ s:String)->String{s}
 static func ocrFailed(_ s:String)->String{s}
}
struct RNG: RandomNumberGenerator { var state:UInt64; mutating func next()->UInt64 {state &+= 0x9e3779b97f4a7c15; var z=state;z=(z^(z>>30)) &* 0xbf58476d1ce4e5b9;z=(z^(z>>27)) &* 0x94d049bb133111eb;return z^(z>>31)};mutating func pick(_ n:Int)->Int{Int(next()%UInt64(n))} }
struct Row {let id:Int;let source:String;let translation:String}
func distance(_ a:String,_ b:String)->Int {let x=Array(a),y=Array(b);var p=Array(0...y.count);for (i,c) in x.enumerated(){var q=[i+1]+Array(repeating:0,count:y.count);for j in y.indices{q[j+1]=min(q[j]+1,p[j+1]+1,p[j]+(c==y[j] ? 0:1))};p=q};return p.last!}
func norm(_ s:String)->String{s.precomposedStringWithCompatibilityMapping.filter{ !$0.isWhitespace && $0 != "\u{200B}" }}
@main struct Bench {
 @MainActor static func main() async throws {
 let args=CommandLine.arguments;guard args.count==8 else {fatalError("usage: bench db label count visionCount seed outputDir scenario(all/S6/synthetic)")}
 let path=args[1],label=args[2],n=Int(args[3])!,vn=Int(args[4])!,seed=UInt64(args[5])!,out=URL(fileURLWithPath:args[6]);var rng=RNG(state:seed)
 var db:OpaquePointer?;guard sqlite3_open_v2(path,&db,SQLITE_OPEN_READONLY,nil)==SQLITE_OK else{fatalError("readonly open")};defer{sqlite3_close(db)}
 var st:OpaquePointer?;sqlite3_prepare_v2(db,"SELECT id,source,machineTrans FROM artificialtrans ORDER BY id",-1,&st,nil);defer{sqlite3_finalize(st)}
 var rows:[Row]=[];var excluded=0
 while sqlite3_step(st)==SQLITE_ROW {guard let s=sqlite3_column_text(st,1),let t=sqlite3_column_text(st,2) else{excluded+=1;continue};let source=String(cString:s),raw=String(cString:t);var trans=raw
 if let obj=try? JSONSerialization.jsonObject(with:Data(raw.utf8)){if let d=obj as? [String:Any]{trans=(["premt","rengong","人工翻译","人工翻譯","pretranslation","translation"]+d.keys.sorted()).compactMap{d[$0] as? String}.first{ !$0.isEmpty } ?? ""}else if let s=obj as? String{trans=s}}
 if source.isEmpty || trans.isEmpty{excluded+=1;continue};rows.append(Row(id:Int(sqlite3_column_int64(st,0)),source:source,translation:trans)) }
 let provider=LunaPretranslationProvider(path:path)
 func run(_ s:String) async throws ->String{try await provider.translate(text:s,from:Locale.Language(identifier:"ja"),to:Locale.Language(identifier:"zh-Hans"))}
 let loadStart=Date();_ = try await run(rows[0].source);let loadMS=Date().timeIntervalSince(loadStart)*1000
 let adjacent=rows.indices.dropLast().filter{rows[$0+1].id==rows[$0].id+1}
 let pairs=[("ー","一"),("ロ","口"),("カ","力"),("ニ","二"),("エ","工"),("タ","夕"),("ト","卜"),("へ","ヘ"),("ベ","べ"),("ぱ","ば"),("ッ","ツ"),("ャ","ヤ")]
 var swaps:[Character:Character]=[:];for(a,b)in pairs{swaps[Character(a)]=Character(b);swaps[Character(b)]=Character(a)}
 var metadata:[String:Any] = ["library":label,"seed":seed,"rows":rows.count,"excluded":excluded,"load_ms":loadMS]
 let scenarios=args[7]=="S6" ? ["S6"] : ["S0","S1","S2-nameLine","S2-sameLine","S3-blank","S3-line","S3-joined","S4-one","S4-two","S5"]+(args[7]=="all" ? ["S6"]:[])
 for scenario in scenarios {
 let file=out.appendingPathComponent("results-\(label)-\(scenario).jsonl");FileManager.default.createFile(atPath:file.path,contents:nil);let handle=try FileHandle(forWritingTo:file);var skipped=0;let start=Date();var order=Array(rows.indices);order.shuffle(using:&rng);let limit=scenario=="S6" ? vn:n;var done=0
 for ix in order {
 if done>=limit {break};if Date().timeIntervalSince(start)>840{break}
 let r=rows[ix];var input=r.source;var expected=[r.translation];var ids=[r.id];var extra:[String:Any]=[:]
 if scenario.hasPrefix("S3") {guard ix<rows.count-1,rows[ix+1].id==r.id+1 else{skipped+=1;continue};let b=rows[ix+1];let sep=scenario=="S3-blank" ? "\n\n":(scenario=="S3-line" ? "\n":"");input+=sep+b.source;expected.append(b.translation);ids.append(b.id)}
 if scenario=="S1" {var chars=Array(input);if chars.count>1 {for _ in 0..<(1+rng.pick(2)){chars.insert("\n",at:1+rng.pick(chars.count-1))};input=String(chars)}}
 if scenario.hasPrefix("S2") {let name=["花子","ヒタキ","山田太郎"][rng.pick(3)];input=name+(scenario=="S2-nameLine" ? "\n":"")+input}
 if scenario.hasPrefix("S4") {var chars=Array(input);var positions=chars.indices.filter{swaps[chars[$0]] != nil};let k=scenario=="S4-one" ? 1:2;guard positions.count>=k else{skipped+=1;continue};positions.shuffle(using:&rng);for j in positions.prefix(k){chars[j]=swaps[chars[j]]!};input=String(chars);extra["edit_distance"]=distance(r.source,input);extra["normalized_edit_distance"]=distance(norm(r.source),norm(input))}
 if scenario=="S5" {input=String(input.prefix(max(1,Int(Double(input.count)*Double(50+rng.pick(31))/100))))}
 if scenario=="S6" {
 let size=24+rng.pick(9),width=18+rng.pick(7),named=done%2==0,dark=done%4>=2;var lines:[String]=[];if named{lines.append("ヒタキ")};let a=Array(r.source);for j in stride(from:0,to:a.count,by:width){lines.append(String(a[j..<min(j+width,a.count)]))}
 let w=(width+3)*size,h=(lines.count+2)*(size+12);let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
 ctx.setFillColor(CGColor(gray:dark ? 0:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:w,height:h));let font=CTFontCreateWithName("HiraginoSans-W3" as CFString,CGFloat(size),nil)
 for(j,line)in lines.enumerated(){let attr:[NSAttributedString.Key:Any]=[.init(kCTFontAttributeName as String):font,.init(kCTForegroundColorAttributeName as String):CGColor(gray:dark ? 1:0,alpha:1)];ctx.textPosition=CGPoint(x:size,y:h-(j+2)*(size+12));CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:line,attributes:attr)),ctx)}
 let os=Date();do{input=try await VisionOCRProvider().recognize(image:ctx.makeImage()!).dialogueText}catch{input="";extra["ocr_error"]=String(describing:error)}
 extra["ocr_ms"]=Date().timeIntervalSince(os)*1000;extra["ocr_text"]=input;extra["rendered_text"]=lines.joined(separator:"\n");extra["edit_distance"]=distance(r.source,input);var clean=input;if named{clean=clean.replacingOccurrences(of:"ヒタキ",with:"")};extra["normalized_edit_distance"]=distance(norm(r.source),norm(clean));extra["font_size"]=size;extra["line_width"]=width;extra["name"]=named;extra["dark"]=dark
 }
 let ts=Date();let actual=try await run(input);let ms=Date().timeIntervalSince(ts)*1000
 // Compare ordered translated spans; miss payload is never mistaken for a translation.
 let pieces=actual.components(separatedBy:"\n\n");let translated=pieces.filter{ !$0.hasPrefix("［预翻译未命中］") && !$0.isEmpty };let exact=actual==expected.joined(separator:"\n\n")
 var remaining=expected;var wrong=false;var hits=0
 for piece in translated {if let i=remaining.firstIndex(of:piece){remaining.remove(at:i);hits+=1}else{wrong=true}}
 let category=exact ? "命中":(wrong ? "误配":(expected.count>1 && hits>0 ? "部分命中":"未命中"))
 extra.merge(["library":label,"scenario":scenario,"id":r.id,"ids":ids,"source":r.source,"source_length":r.source.count,"normalized_length":norm(r.source).count,"input":input,"expected":expected.joined(separator:"\n\n"),"actual":actual,"category":category,"elapsed_ms":ms,"has_miss_marker":actual.contains("［预翻译未命中］")]){_,b in b}
 try handle.write(contentsOf:JSONSerialization.data(withJSONObject:extra,options:[.sortedKeys]));try handle.write(contentsOf:Data("\n".utf8));done+=1
 }
 try handle.close();metadata[scenario]=["tested":done,"skipped":skipped,"seconds":Date().timeIntervalSince(start)];print("\(label) \(scenario): \(done), skipped \(skipped)")
 }
 // Round 2 scenes run after every legacy RNG operation, with a separate RNG.
 var realRNG = RNG(state: seed ^ 0x52327265616c)
 let eligible = rows.filter { ["「","『","（","("].contains(String($0.source.prefix(1))) }
 let sourceKeys = Set(rows.map { norm($0.source) })
 let phraseRegex = try NSRegularExpression(pattern: "[「『][^「『」』]{1,20}[」』]")
 let risks = rows.filter { row in
     let key = norm(row.source)
     return phraseRegex.matches(in:key,range:NSRange(key.startIndex...,in:key)).contains { match in
         let phrase = String(key[Range(match.range,in:key)!])
         return phrase != key && sourceKeys.contains(phrase)
     }
 }
 let parentheses = rows.filter { row in
     let key = norm(row.source)
     return !key.hasPrefix("(") && key.contains("(") && key.contains(")")
 }
 func writeScene(_ scene:String, _ cases:[(Row,String,String)]) async throws {
     let file=out.appendingPathComponent("results-\(label)-\(scene).jsonl")
     FileManager.default.createFile(atPath:file.path,contents:nil)
     let handle=try FileHandle(forWritingTo:file);let start=Date()
     for (r,input,kind) in cases {
         let ts=Date();let actual=try await run(input);let ms=Date().timeIntervalSince(ts)*1000
         let translated=actual.components(separatedBy:"\n\n").filter{ !$0.hasPrefix("［预翻译未命中］") && !$0.isEmpty }
         let category=actual==r.translation ? "命中" : (translated.isEmpty ? "未命中" : "误配")
         let record:[String:Any] = ["library":label,"scenario":scene,"id":r.id,"ids":[r.id],"source":r.source,"source_length":r.source.count,"normalized_length":norm(r.source).count,"input":input,"expected":r.translation,"actual":actual,"category":category,"elapsed_ms":ms,"has_miss_marker":actual.contains("［预翻译未命中］"),"risk_kind":kind]
         try handle.write(contentsOf:JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]));try handle.write(contentsOf:Data("\n".utf8))
     }
     try handle.close();metadata[scene]=["tested":cases.count,"seconds":Date().timeIntervalSince(start)]
 }
 var realOrder=eligible;realOrder.shuffle(using:&realRNG)
 try await writeScene("S2-real",Array(realOrder.prefix(n)).enumerated().map { i,r in
     (r,"ヒタキ"+(i%2==0 ? "\n":"")+r.source,String(r.source.prefix(1)))
 })
 var riskCases:[(Row,String,String)]=[]
 for (kind,group) in [("parentheses",parentheses),("embedded-quotes",risks)] {
     for r in group {
         var chars=Array(r.source)
         if let i=chars.indices.first(where:{ swaps[chars[$0]] != nil }) { chars[i]=swaps[chars[i]]! }
         else if let i=chars.indices.first(where:{ String(chars[$0]).range(of:"[\\p{Han}\\p{Hiragana}\\p{Katakana}]",options:.regularExpression) != nil }) { chars[i] = chars[i] == "誤" ? "字":"誤" }
         riskCases += [(r,r.source,kind+"-original"),(r,"ヒタキ\n"+r.source,kind+"-name"),(r,String(chars),kind+"-typo")]
         // Parentheses also need the separately requested soft-wrap safety check.
         if kind == "parentheses" {let a=Array(r.source);let mid=a.count/2;riskCases.append((r,String(a[..<mid])+"\n"+String(a[mid...]),kind+"-wrap"))}
     }
 }
 try await writeScene("S7-risk",riskCases)
 metadata["risk_rows"]=["parentheses":parentheses.count,"embedded_quotes":risks.count]

 // Round 3: appended after all prior scenarios; independent sampling stream.
 var r3rng = RNG(state: seed ^ 0x52336e616d6573)
 var r3order = eligible; r3order.shuffle(using: &r3rng)
 let r3sample = Array(r3order.prefix(n))
 for (layout, separator) in [("line","\n"),("space"," "),("attached","")] {
     let names = ["お母さん","女の子","テラくん","あかり","生徒１","シーマ"]
     try await writeScene("S2-names-"+layout, r3sample.enumerated().map { i,r in
         let name = names[i % names.count]
         return (r,name+separator+r.source,name)
     })
 }
 let openRows = r3sample.filter { norm($0.source).count >= 28 && ["」","』","）",")"].contains(String($0.source.suffix(1))) }
 for named in [false,true] {
     try await writeScene("S2-open-"+(named ? "named":"bare"), openRows.map { r in
         (r,(named ? "ヒタキ\n":"")+String(r.source.dropLast()),"missing-close")
     })
 }
 var spaceOrder = Array(adjacent.filter { i in
     ["「","『","（","("].contains(String(rows[i].source.prefix(1))) &&
     ["「","『","（","("].contains(String(rows[i+1].source.prefix(1)))
 }); spaceOrder.shuffle(using:&r3rng)
 // Pair classification mirrors legacy S3: identify partial hits separately from wrong translations.
 let spaceFile=out.appendingPathComponent("results-\(label)-S3-space.jsonl")
 FileManager.default.createFile(atPath:spaceFile.path,contents:nil)
 let spaceHandle=try FileHandle(forWritingTo:spaceFile)
 for (j,i) in spaceOrder.prefix(n).enumerated() {
     let r=rows[i], b=rows[i+1], expected=[r.translation,b.translation]
     let sep = j%2 == 0 ? " " : "　"
     let named = j%4 < 2
     let input=(named ? "ヒタキ":"")+r.source+sep+(named ? "ツグミ":"")+b.source
     let ts=Date();let actual=try await run(input);let ms=Date().timeIntervalSince(ts)*1000
     let translated=actual.components(separatedBy:"\n\n").filter{ !$0.hasPrefix("［预翻译未命中］") && !$0.isEmpty }
     var remaining=expected;var wrong=false;var hits=0
     for piece in translated {if let k=remaining.firstIndex(of:piece){remaining.remove(at:k);hits+=1}else{wrong=true}}
     let category=actual==expected.joined(separator:"\n\n") ? "命中":(wrong ? "误配":(hits>0 ? "部分命中":"未命中"))
     let record:[String:Any] = ["library":label,"scenario":"S3-space","id":r.id,"ids":[r.id,b.id],"source":r.source,"source_length":r.source.count,"normalized_length":norm(r.source).count,"input":input,"expected":expected.joined(separator:"\n\n"),"actual":actual,"category":category,"elapsed_ms":ms,"has_miss_marker":actual.contains("［预翻译未命中］"),"name":named,"separator":sep]
     try spaceHandle.write(contentsOf:JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]));try spaceHandle.write(contentsOf:Data("\n".utf8))
 }
 try spaceHandle.close()
 metadata["S3-space"]=["tested":min(n,spaceOrder.count)]

 // Round 3b: appended after all old scenarios, with an independent random stream.
 var patchRNG = RNG(state: seed ^ 0x5233626669727374)
 func patchLoose(_ s:String)->String {
     norm(s).replacingOccurrences(of:"[.・•⋯]{2,}|⋯",with:"…",options:.regularExpression)
         .replacingOccurrences(of:"[―─—–ー一-]{2,}",with:"―",options:.regularExpression)
 }
 let patchStrictKeys = Set(rows.map { norm($0.source) })
 let patchLooseKeys = Set(rows.map { patchLoose($0.source) })
 func patchFirst(_ r:Row)->Bool {
     let s=norm(r.source)
     return !s.isEmpty && s.count <= 20 && s.range(of:"[\\p{Hiragana}]",options:.regularExpression) != nil
         && s.range(of:"^[\\p{Han}\\p{Katakana}\\p{Hiragana}A-Za-z0-9ー・]*$",options:.regularExpression) != nil
         && !s.contains(where:{ "「」『』()（）。、！？!?".contains($0) })
 }
 func patchQuote(_ r:Row)->Bool { ["「","『","（"].contains(String(r.source.prefix(1))) }
 let patchEligible = rows.indices.filter { patchFirst(rows[$0]) }
 var patchAdjacent = patchEligible.filter { i in i+1 < rows.count && rows[i+1].id == rows[i].id+1 && patchQuote(rows[i+1]) }
 patchAdjacent.shuffle(using:&patchRNG)
 var patchOther = patchEligible.filter { !patchAdjacent.contains($0) }; patchOther.shuffle(using:&patchRNG)
 let patchQuoted = rows.filter { patchQuote($0) }
 var patchPairs:[(Row,Row)] = patchAdjacent.prefix(n).map { (rows[$0],rows[$0+1]) }
 for i in patchOther where patchPairs.count < n {
     patchPairs.append((rows[i],patchQuoted[patchRNG.pick(patchQuoted.count)]))
 }
 // Same ordered-span classification as legacy S3; unchanged expectations for OCR damage.
 func writePatch(_ scene:String,_ cases:[(Row,Row,String,[String:Any])]) async throws {
     let file=out.appendingPathComponent("results-\(label)-\(scene).jsonl")
     FileManager.default.createFile(atPath:file.path,contents:nil)
     let handle=try FileHandle(forWritingTo:file)
     for (r,b,input,extra) in cases {
         let expected=[r.translation,b.translation]
         let ts=Date();let actual=try await run(input);let ms=Date().timeIntervalSince(ts)*1000
         let translated=actual.components(separatedBy:"\n\n").filter { !$0.hasPrefix("［预翻译未命中］") && !$0.isEmpty }
         var remaining=expected;var hits=0;var wrong=false
         for piece in translated {if let k=remaining.firstIndex(of:piece){remaining.remove(at:k);hits+=1}else{wrong=true}}
         let category=actual==expected.joined(separator:"\n\n") ? "命中":(wrong ? "误配":(hits>0 ? "部分命中":"未命中"))
         var record:[String:Any] = ["library":label,"scenario":scene,"id":r.id,"ids":[r.id,b.id],"source":r.source,"source_length":r.source.count,"normalized_length":norm(r.source).count,"input":input,"expected":expected.joined(separator:"\n\n"),"actual":actual,"category":category,"elapsed_ms":ms,"has_miss_marker":actual.contains("［预翻译未命中］")]
         record.merge(extra){_,b in b}
         try handle.write(contentsOf:JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]));try handle.write(contentsOf:Data("\n".utf8))
     }
     try handle.close();metadata[scene]=["tested":cases.count]
 }
 try await writePatch("S3-firstline",patchPairs.map { r,b in
     (r,b,r.source+"\n"+b.source,["firstline_length":norm(r.source).count,"adjacent":b.id==r.id+1])
 })
 var patchMiss:[(Row,Row,String,[String:Any])] = []
 for (r,b) in patchPairs {
     var chars=Array(norm(r.source));var positions=Array(chars.indices);positions.shuffle(using:&patchRNG)
     var changed:String? = nil
     for i in positions {
         for replacement:Character in ["誤","字","仮"] where replacement != chars[i] {
             var candidate=chars;candidate[i]=replacement;let key=String(candidate)
             if !patchStrictKeys.contains(key) && !patchLooseKeys.contains(patchLoose(key)) { changed=key;break }
         }
         if changed != nil {break}
     }
     if let changed {
         patchMiss.append((r,b,changed+"\n"+b.source,["firstline_length":changed.count,"firstline_original":r.source,"firstline_changed":changed,"strict_absent":true,"loose_absent":true,"edit_distance":distance(norm(r.source),changed)]))
     }
 }
 try await writePatch("S3-firstline-miss",patchMiss)
 var patchOCROrder = Array(adjacent.filter { i in rows[i].source.hasPrefix("「") && rows[i].source.hasSuffix("」") && rows[i+1].source.hasPrefix("「") })
 patchOCROrder.shuffle(using:&patchRNG)
 var patchOCRCases:[(Row,Row,String,[String:Any])] = []
 for i in patchOCROrder.prefix(n) {
     let r=rows[i],b=rows[i+1]
     for gap in [10.0,30.0] {
         let first=String(r.source.dropLast())
         let blocks=[OCRTextBlock(text:first,boundingBox:CGRect(x:20,y:100,width:600,height:20)),
                     OCRTextBlock(text:b.source,boundingBox:CGRect(x:20,y:80-gap,width:600,height:20))]
         let input=OCRResult(text:"",detectedLanguage:nil,confidence:1,blocks:blocks).dialogueText
         patchOCRCases.append((r,b,input,["gap":gap,"line_height":20,"gap_class":gap>18 ? "large":"small","blocks":[first,b.source],"boxes":[[20.0,100.0,600.0,20.0],[20.0,80-gap,600.0,20.0]]]))
     }
 }
 try await writePatch("S3-ocr-open",patchOCRCases)
 metadata["patch_firstline_population"] = Dictionary(grouping:patchEligible,by:{norm(rows[$0].source).count}).mapValues{$0.count}.reduce(into:[String:Int]()){$0[String($1.key)]=$1.value}
 metadata["patch_adjacent_available"]=patchAdjacent.count

 metadata["adjacent_pairs"]=adjacent.count
 try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("metadata-\(label)-\(args[7]).json"))
 }
}
