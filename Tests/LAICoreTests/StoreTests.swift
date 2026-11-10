import Foundation
import Testing
import PDFKit
@testable import LAICore
@Test func persistenceSurvivesReopenAndDeletesAll() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Prueba café",settings:AppSettings()); try await store.save(session)
    let segment=TranscriptSegment(sessionID:session.id,source:.system,start:12,end:15,text:"Acordamos revisar el informe.")
    try await store.append(segment); try await store.append(segment)
    var partial=segment; partial.isFinal=false; partial.text="parcial"; try await store.append(partial)
    let rows=try await store.segments(session:session.id)
    #expect(rows.count==1); #expect(rows[0].1.text==segment.text)
    #expect(try await store.sessions(search:"CAFÉ").count==1)
    #expect(try await store.segments(session:session.id,search:"revisar").count==1)
    #expect(try await store.segments(session:session.id,search:"%").isEmpty)
    let second=try SessionStore(directory:directory)
    #expect(try await second.sessions().first?.id==session.id)
    try await second.recoverInterrupted(); #expect(try await second.sessions().first?.status=="interrupted")
    let snapshot=SummarySnapshot(sessionID:session.id,throughRow:rows[0].0,isFinal:true,findings:[]); try await store.save(snapshot)
    #expect(try await store.latestSummary(session:session.id)?.isFinal==true)
    let audioFolder=directory.appendingPathComponent(session.id.uuidString); try FileManager.default.createDirectory(at:audioFolder,withIntermediateDirectories:true)
    try Data([1,2,3]).write(to:audioFolder.appendingPathComponent("system.caf"))
    try await store.delete(session:session.id)
    #expect(try await store.sessions().isEmpty); #expect(try await store.segments(session:session.id).isEmpty)
    #expect(try await store.latestSummary(session:session.id)==nil)
    #expect(!FileManager.default.fileExists(atPath:audioFolder.path))
}
@Test func deletionPurgesRelatedDataAndReclaimsSpaceWhenHistoryIsEmpty() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let directory=root.appendingPathComponent("app")
    let store=try SessionStore(directory:directory)
    var deleted=Session(title:"SessionPurgeMarker",settings:AppSettings())
    deleted.status="completed"
    var survivor=Session(title:"Sesión conservada",settings:AppSettings())
    survivor.status="completed"
    try await store.save(deleted)
    try await store.save(survivor)
    let original=root.appendingPathComponent("original.caf")
    let exported=root.appendingPathComponent("exportado.txt")
    try Data([1,2,3]).write(to:original)
    try Data("Archivo del usuario".utf8).write(to:exported)

    let transcript=TranscriptSegment(sessionID:deleted.id,source:.system,start:0,end:8,
                                     text:"TranscriptPurgeMarker "+String(repeating:"contenido ",count:16384))
    let kept=TranscriptSegment(sessionID:survivor.id,source:.file,start:0,end:4,text:"Texto de otra sesión")
    try await store.append(transcript)
    try await store.append(kept)
    let row=try #require(try await store.segments(session:deleted.id).first)
    let finding=Finding(kind:.decision,text:"SummaryPurgeMarker",segmentID:transcript.id,
                        quote:"TranscriptPurgeMarker",start:0,end:8)
    try await store.save(SummarySnapshot(sessionID:deleted.id,throughRow:row.0,isFinal:true,findings:[finding]))
    try await store.correctSegment(session:deleted.id,id:transcript.id,text:"CorrectedPurgeMarker")
    try await store.saveAudioBookmark(Data("AudioBookmarkPurgeMarker".utf8),session:deleted.id)
    try await store.save(SessionBookmark(sessionID:deleted.id,time:0,note:"NotePurgeMarker"))
    try await store.requestFinalSummary(session:deleted.id)
    try await store.save(SummaryRunMetrics(sessionID:deleted.id,seconds:1,cpuSeconds:0.1,clientFootprintMB:1,
                                           pendingSegments:1,processedBatches:1,contextReductions:0,
                                           throughRow:row.0,final:true,outcome:"MetricsPurgeMarker"))
    let archivePath=directory.appendingPathComponent(deleted.id.uuidString)
    let archive=AudioArchive(directory:archivePath)
    for input in [AudioSource.system,.microphone] {
        try await archive.append(AudioChunk(samples:[0.1,-0.1],sampleRate:16000,start:0,source:input))
    }
    await archive.close()
    #expect(try Set(FileManager.default.contentsOfDirectory(atPath:archivePath.path))==["system.caf","microphone.caf","timing.jsonl"])

    try await store.delete(session:deleted.id)
    #expect(try await store.session(id:deleted.id)==nil)
    #expect(try await store.segments(session:deleted.id).isEmpty)
    #expect(try await store.latestSummary(session:deleted.id)==nil)
    #expect(try await store.findings(session:deleted.id,template:.meeting).isEmpty)
    #expect(try await store.bookmarks(session:deleted.id).isEmpty)
    #expect(try await store.audioBookmark(session:deleted.id)==nil)
    #expect(try await store.transcriptRevision(session:deleted.id)==0)
    #expect(try await store.pendingFinalSession()==nil)
    #expect(try await store.summaryMetrics(session:deleted.id).isEmpty)
    #expect(try await store.searchTranscripts("CorrectedPurgeMarker").isEmpty)
    #expect(try await store.searchTranscripts("TranscriptPurgeMarker").isEmpty)
    #expect(try await !store.updateExistingSession(deleted))
    #expect(try await store.segments(session:survivor.id).first?.1==kept)
    #expect(!FileManager.default.fileExists(atPath:archivePath.path))
    #expect(try Data(contentsOf:original)==Data([1,2,3]))
    #expect(try Data(contentsOf:exported)==Data("Archivo del usuario".utf8))
    let database=directory.appendingPathComponent("sessions.sqlite")
    let afterOneDeletion=try Data(contentsOf:database)
    for marker in ["SessionPurgeMarker","TranscriptPurgeMarker","CorrectedPurgeMarker","SummaryPurgeMarker","NotePurgeMarker","MetricsPurgeMarker"] {
        #expect(afterOneDeletion.range(of:Data(marker.utf8))==nil)
    }

    try await store.delete(session:survivor.id)
    let wal=directory.appendingPathComponent("sessions.sqlite-wal")
    #expect(((try? Data(contentsOf:wal)) ?? Data()).isEmpty)
    let reopened=try SessionStore(directory:directory)
    #expect(try await reopened.sessions().isEmpty)
    #expect(try Data(contentsOf:database).count<afterOneDeletion.count)
    // Reopening can write schema configuration. Neither file may retain
    // the test markers from the deleted session.
    let journal=(try? Data(contentsOf:wal)) ?? Data()
    #expect(journal.range(of:Data("CorrectedPurgeMarker".utf8))==nil)
}
@Test func exportFormatsAndSelection() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory); let session=Session(title:"Exportación ñ",settings:AppSettings()); try await store.save(session)
    for i in 0..<240 { try await store.append(.init(sessionID:session.id,source:.system,start:Double(i),end:Double(i+1),text:"Fragmento \(i) con palabras españolas y English.")) }
    let exporter=SessionExporter(store:store)
    for format in ExportFormat.allCases {
        let url=directory.appendingPathComponent("export.\(format.rawValue)")
        try await exporter.export(session:session,to:url,format:format,options:ExportOptions())
        let data=try Data(contentsOf:url); #expect(data.count>100)
        if format == .json { let json=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any]); #expect((json["transcript"] as? [[String:Any]])?.count==240) }
        if format == .pdf {
            #expect(String(decoding:data.prefix(4),as:UTF8.self)=="%PDF")
            let document=try #require(PDFDocument(data:data))
            #expect(document.pageCount>1)
            #expect(document.string?.contains("Fragmento 239")==true)
            #expect(document.string?.contains("españolas")==true)
        }
        if format == .txt || format == .markdown { #expect(String(decoding:data,as:UTF8.self).contains("Fragmento 239")) }
    }
    var options=ExportOptions(); options.transcript=false
    let url=directory.appendingPathComponent("export.json")
    try await exporter.export(session:session,to:url,format:.json,options:options)
    let json=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); #expect((json["transcript"] as? [[String:Any]])?.isEmpty==true)
}
