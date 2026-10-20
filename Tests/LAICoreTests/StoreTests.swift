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
    let url=directory.appendingPathComponent("summary.json"); try await exporter.export(session:session,to:url,format:.json,options:options)
    let json=try #require(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]); #expect((json["transcript"] as? [[String:Any]])?.isEmpty==true)
}
