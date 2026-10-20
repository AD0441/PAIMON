import Foundation
import Testing
import CSQLite
import PDFKit
@testable import LAICore

@Test func bookmarksPersistEditPaginateAndDeleteWithSession() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Marcadores",settings:AppSettings()); try await store.save(session)
    let segment=TranscriptSegment(sessionID:session.id,source:.system,start:8,end:15,text:"El concepto principal se explica en este fragmento.")
    try await store.append(segment)
    var marker=SessionBookmark(sessionID:session.id,time:10,note:"Revisar después",segmentID:segment.id)
    try await store.save(marker)
    marker.note="Nota corregida"; try await store.save(marker)
    for time in 20..<130 { try await store.save(SessionBookmark(sessionID:session.id,time:Double(time))) }
    let reopened=try SessionStore(directory:directory)
    let first=try await reopened.bookmarks(session:session.id)
    #expect(first.count==100); #expect(first.first?.note=="Nota corregida")
    #expect(try await reopened.bookmarks(session:session.id,offset:100).count==11)
    #expect(try await store.segmentID(session:session.id,at:10)==segment.id)
    #expect(try await store.bookmarkPage(containing:marker)==0)
    try await store.deleteBookmark(marker.id)
    #expect(try await store.bookmarks(session:session.id).contains{$0.id==marker.id}==false)
    try await store.delete(session:session.id)
    #expect(try await store.bookmarks(session:session.id).isEmpty)
    #expect(try await store.searchTranscripts("concepto").isEmpty)
}
@Test func fullTextSearchHandlesAccentsPrefixesUpdatesAndLiteralOperators() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let a=Session(title:"Clase de física",settings:AppSettings()),b=Session(title:"Reunión",settings:AppSettings())
    try await store.save(a); try await store.save(b)
    var segment=TranscriptSegment(sessionID:a.id,source:.system,start:20,end:30,text:"La energía eléctrica permite preparar café.")
    try await store.append(segment)
    try await store.append(.init(sessionID:b.id,source:.microphone,start:5,end:10,text:"Acordamos revisar el presupuesto."))
    let results=try await store.searchTranscripts("ENERGIA electri")
    #expect(results.count==1); #expect(results.first?.sessionID==a.id); #expect(results.first?.start==20)
    #expect(try await store.searchTranscripts("cafe").count==1)
    #expect(try await store.searchTranscripts("\" OR * %").isEmpty)
    #expect(try await store.searchTranscripts("% * ()").isEmpty)
    segment.text="Texto corregido sobre corriente continua."; try await store.append(segment)
    #expect(try await store.searchTranscripts("cafe").isEmpty)
    #expect(try await store.searchTranscripts("corriente").count==1)
    var partial=segment; partial.isFinal=false; partial.text="Palabra parcialinvisible"; try await store.append(partial)
    #expect(try await store.searchTranscripts("parcialinvisible").isEmpty)
    try await store.delete(session:a.id)
    #expect(try await store.searchTranscripts("corriente").isEmpty)
    #expect(try await store.searchTranscripts("presup").first?.sessionID==b.id)
}
@Test func legacyIndexBackfillResumesAndIndexesNewRowsImmediately() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:directory) }
    var db:OpaquePointer?
    #expect(sqlite3_open(directory.appendingPathComponent("sessions.sqlite").path,&db)==SQLITE_OK)
    let session=Session(title:"Historial anterior",settings:AppSettings())
    func sql(_ text:String) throws { guard sqlite3_exec(db,text,nil,nil,nil)==SQLITE_OK else { throw LAIError.message("Fixture SQLite: \(String(cString:sqlite3_errmsg(db)))") } }
    try sql("CREATE TABLE sessions(id TEXT PRIMARY KEY,created REAL NOT NULL,data TEXT NOT NULL); CREATE TABLE segments(seq INTEGER PRIMARY KEY AUTOINCREMENT,session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,id TEXT NOT NULL,start REAL NOT NULL,data TEXT NOT NULL,UNIQUE(session,id)); PRAGMA user_version=1;")
    func json<T:Encodable>(_ value:T) throws -> String { String(decoding:try JSONEncoder().encode(value),as:UTF8.self).replacingOccurrences(of:"'",with:"''") }
    try sql("INSERT INTO sessions VALUES('\(session.id)',0,'\(try json(session))');")
    for i in 0..<250 {
        let segment=TranscriptSegment(sessionID:session.id,source:.system,start:Double(i),end:Double(i+1),text:"Histórico elemento\(i) sobre tecnología.")
        try sql("INSERT INTO segments(session,id,start,data) VALUES('\(session.id)','\(segment.id)',\(i),'\(try json(segment))');")
    }
    sqlite3_close(db)
    let store=try SessionStore(directory:directory)
    #expect(try await store.searchTranscripts("elemento249").isEmpty)
    #expect(try await store.indexNextSearchBatch()==false)
    #expect(try await store.searchTranscripts("elemento0").count==1)
    #expect(try await store.searchTranscripts("elemento249").isEmpty)
    let resumed=try SessionStore(directory:directory)
    try await resumed.append(.init(sessionID:session.id,source:.system,start:500,end:501,text:"Nuevo registro inmediato."))
    #expect(try await resumed.searchTranscripts("inmediato").count==1)
    while try await resumed.indexNextSearchBatch()==false {}
    #expect(try await resumed.searchTranscripts("elemento249").count==1)
    #expect(try await resumed.searchTranscripts("historico",limit:100).count==100)
}
actor TemplateFixtureEngine:SummarizationEngine {
    let template:SummaryTemplate
    var sourceCalls=0
    init(_ template:SummaryTemplate) { self.template=template }
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) -> [Finding] {
        if !segments.isEmpty { sourceCalls += 1 }
        return EvidenceValidator.merge(previous:previous,new:segments.map { Finding(kind:template == .lecture ? .concept:.idea,text:$0.text,segmentID:$0.id,quote:$0.text,start:$0.start,end:$0.end) })
    }
    func unload() {}
}
@Test func changingTemplateReprocessesOriginalWithoutExtraNormalPasses() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Plantillas",settings:AppSettings()); try await store.save(session)
    try await store.append(.init(sessionID:session.id,source:.system,start:0,end:10,text:"La corriente se mide en amperios."))
    let coordinator=SummaryCoordinator(store:store)
    let meeting=TemplateFixtureEngine(.meeting)
    _=try await coordinator.update(session:session,engine:meeting,final:true)
    _=try await coordinator.update(session:session,engine:meeting,final:false)
    #expect(await meeting.sourceCalls==1)
    session.summaryTemplate = .lecture; try await store.save(session)
    let lecture=TemplateFixtureEngine(.lecture)
    let changed=try #require(try await coordinator.update(session:session,engine:lecture,final:true))
    #expect(changed.summaryTemplate == .lecture)
    #expect(changed.findings.first?.kind == .concept)
    #expect(await lecture.sourceCalls==1)
    #expect(try await store.segments(session:session.id).count==1)
    #expect(try await store.sessions().first?.template == .lecture)
    for template in SummaryTemplate.allCases { #expect(FoundationSummaryEngine.instructions(for:template).contains("No inventes")) }
}
@Test func oldSettingsAndSessionsKeepTheirPreferences() throws {
    var settings=AppSettings(); settings.locale="en-US"; settings.summaryInterval=180
    var object=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
    object.removeValue(forKey:"summaryTemplate")
    let decoded=try JSONDecoder().decode(AppSettings.self,from:JSONSerialization.data(withJSONObject:object))
    #expect(decoded.locale=="en-US"); #expect(decoded.summaryInterval==180)
    let legacy=Session(title:"Anterior",settings:decoded)
    let reopened=try JSONDecoder().decode(Session.self,from:JSONEncoder().encode(legacy))
    #expect(reopened.template == .meeting)
}
@Test func bookmarkExportsPageThroughAllNotesAndRespectSelection() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Notas de clase",settings:AppSettings()); try await store.save(session)
    for i in 0..<101 { try await store.save(SessionBookmark(sessionID:session.id,time:Double(i),note:"Anotación número \(i)")) }
    var options=ExportOptions(); options.transcript=false
    let exporter=SessionExporter(store:store)
    for format in ExportFormat.allCases {
        let url=directory.appendingPathComponent("notes.\(format.rawValue)")
        try await exporter.export(session:session,to:url,format:format,options:options)
        if format == .json {
            let object=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
            #expect((object["bookmarks"] as? [[String:Any]])?.count==101)
        } else if format == .pdf { #expect(PDFDocument(url:url)?.string?.contains("Anotación número 100")==true) }
        else { #expect(try String(contentsOf:url,encoding:.utf8).contains("Anotación número 100")) }
    }
    options.bookmarks=false
    let url=directory.appendingPathComponent("without-notes.json")
    try await exporter.export(session:session,to:url,format:.json,options:options)
    let object=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
    #expect((object["bookmarks"] as? [[String:Any]])?.isEmpty==true)
}
