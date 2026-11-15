import Foundation
import PDFKit
import Testing
import CSQLite
@testable import LAICore

@Test func richAnalysisExportsAllStoredAssistantTurnsAndNumericDataWithoutRawVectors() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Datos sintéticos",settings:AppSettings()); session.status="completed"
    try await store.save(session)
    let text="Acordamos comprar dos micrófonos."
    let segment=TranscriptSegment(sessionID:session.id,source:.file,start:0,end:5,text:text)
    try await store.append(segment)
    let evidence=FindingEvidence(segmentID:segment.id,quote:text,start:0,end:5)
    let reply=TranscriptAssistantReply(text:"Comprar dos micrófonos.",evidence:[evidence],sampled:true)
    for index in 0..<137 {
        try await store.saveAssistantTurn(AssistantTurn(sessionID:session.id,revision:0,question:"Pregunta sintética "+String(index),reply:reply))
    }
    let recent=try await store.assistantTurns(session:session.id,limit:12,newest:true)
    #expect(recent.count==12 && recent.last?.question=="Pregunta sintética 136")
    var point=SentimentPoint(id:0,segmentID:segment.id,time:0,excerpt:text,speaker:nil,speakerNumber:nil,score:0)
    point.rawAppleScore = -0.8; point.polarity = .neutral
    try await store.saveSentiment(.init(points:[point],tagging:.complete,tagged:1),session:session.id,
                                  stamp:store.sentimentStamp(session:session.id))
    let voice=VocalPoint(id:0,start:0,end:3,level:-21,pitch:200,pitchVariation:4,quietSeconds:0.2,measuredSeconds:3,audioStart:0,audioEnd:3)
    let neural=VocalEmotionReport(points:[
        .init(start:0,end:3,audioStart:0,audioEnd:3,emotion:.neutral,confidence:0.8,embedding:[1,0]),
        .init(start:4,end:7,audioStart:4,audioEnd:7,emotion:.joy,confidence:0.9,embedding:[0,1])
    ],sampled:false)
    try await store.saveVocalAnalysis(session:session.id,source:.file,measurements:[voice],emotions:neural,
        sounds:.init(events:[.init(kind:.other("speech"),start:0,end:3,audioStart:0,audioEnd:3)],limited:false),soundIdentifiers:["speech"])
    let saved=try await store.savedVocalAnalysis(session:session.id)
    #expect(saved[0].emotions?.points.allSatisfy{$0.embedding==nil}==true)
    #expect(saved[0].distances?.first?.distance==1)
    let reopened=try SessionStore(directory:directory)
    #expect(try await reopened.assistantTurns(session:session.id,limit:100).count==100)
    var options=ExportOptions(); options.transcript=false; options.kinds=[]; options.bookmarks=false
    options.sentiments=true; options.assistant=true
    for format in ExportFormat.allCases {
        let url=directory.appendingPathComponent("analysis."+format.rawValue)
        try await SessionExporter(store:store).export(session:session,to:url,format:format,options:options)
        let content:String
        if format == .pdf { content=try #require(PDFDocument(url:url)?.string) }
        else { content=try String(contentsOf:url,encoding:.utf8) }
        #expect(content.contains("Pregunta sintética 136"))
        #expect(!content.contains("El resumen todavía no está disponible."))
        if format == .json {
            let json=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
            #expect((json["assistant"] as? [[String:Any]])?.count==137)
            let sentiments=try #require(json["sentiments"] as? [String:Any])
            let text=try #require(sentiments["text"] as? [String:Any])
            let report=try #require(text["report"] as? [String:Any])
            let points=try #require(report["points"] as? [[String:Any]])
            #expect(points[0]["score"] as? Double==0)
            #expect(points[0]["rawAppleScore"] as? Double == -0.8)
            #expect(text["engine"] as? String=="Apple Foundation Models")
            #expect(!content.contains("\"embedding\""))
            #expect(content.contains("\"distance\":1"))
        } else {
            #expect(content.contains("-0.800"))
            #expect(content.contains("200.000"))
        }
    }
    try await store.delete(session:session.id)
    #expect(try await store.assistantTurns(session:session.id).isEmpty)
    #expect(try await store.savedVocalAnalysis(session:session.id).isEmpty)
    #expect(try await store.sentimentForExport(session:session.id)==nil)
}

@Test func assistantPersistenceRejectsStaleOrInventedEvidenceAndRetainsHistoricalRevision() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Revisión",settings:AppSettings()); session.status="completed"; try await store.save(session)
    let segment=TranscriptSegment(sessionID:session.id,source:.file,start:0,end:5,text:"La entrega será el lunes.")
    try await store.append(segment)
    let evidence=FindingEvidence(segmentID:segment.id,quote:segment.text,start:0,end:5)
    let turn=AssistantTurn(sessionID:session.id,revision:0,question:"¿Cuándo será la entrega?",reply:.init(text:"El lunes.",evidence:[evidence],sampled:false))
    try await store.saveAssistantTurn(turn)
    _=try await store.correctSegment(session:session.id,id:segment.id,text:"La entrega será el martes.")
    await #expect(throws:(any Error).self) { try await store.saveAssistantTurn(turn) }
    #expect(try await store.assistantTurns(session:session.id).first?.transcriptRevision==0)
    let fabricated=AssistantTurn(sessionID:session.id,revision:1,question:"¿Cuándo?",reply:.init(text:"El viernes.",evidence:[evidence],sampled:false))
    await #expect(throws:(any Error).self) { try await store.saveAssistantTurn(fabricated) }
    let abstention=AssistantTurn(sessionID:session.id,revision:1,question:"¿Dónde?",reply:.init(text:nil,evidence:[],sampled:true))
    try await store.saveAssistantTurn(abstention)
    #expect(try await store.assistantTurns(session:session.id).count==2)
}

@Test func legacyPolarityExportKeepsOriginalValuesInsteadOfRewritingThemAsNeutral() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Legado",settings:AppSettings()); session.status="completed"; try await store.save(session)
    try await store.saveSentiment(.init(points:[.init(id:0,segmentID:"file-0",time:0,excerpt:"Información",speaker:nil,speakerNumber:nil,score:-1)],tagging:.unavailable,tagged:0),session:session.id,stamp:store.sentimentStamp(session:session.id))
    var db:OpaquePointer?; #expect(sqlite3_open(directory.appendingPathComponent("sessions.sqlite").path,&db)==SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db,"UPDATE transcript_sentiment SET version=1",nil,nil,nil)==SQLITE_OK)
    #expect(try await store.cachedSentiment(session:session.id)==nil)
    #expect(try await store.sentimentNeedsRefresh(session:session.id))
    let legacy=try #require(try await store.sentimentForExport(session:session.id))
    #expect(legacy.version==1 && legacy.engine=="NaturalLanguage")
    #expect(legacy.report.points[0].score == -1)
}

@Test func sentimentExportStampIsStableAndDetectsSpeakerCacheInvalidation() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var settings=AppSettings(); settings.diarizationEnabled=true
    var session=Session(title:"Hablantes sintéticos",settings:settings); session.status="completed"
    try await store.save(session)
    let segment=TranscriptSegment(sessionID:session.id,source:.file,start:0,end:5,text:"El informe tiene tres secciones.")
    try await store.append(segment)
    try await store.appendSpeakerTurns([.init(speaker:"A",start:0,end:5)],source:.file,session:session.id)
    try await store.saveSentiment(.init(points:[],tagging:.complete,tagged:0),session:session.id,stamp:store.sentimentStamp(session:session.id))
    let before=try await store.analysisExportStamp(session:session.id)
    #expect(try await store.analysisExportStamp(session:session.id)==before)
    let speaker=try #require(try await store.speakers(for:[segment],session:session.id).values.first)
    try await store.renameSpeaker(session:session.id,id:speaker.id,name:"Voz de prueba")
    #expect(try await store.analysisExportStamp(session:session.id) != before)
    #expect(try await store.sentimentForExport(session:session.id)==nil)
}
