import Foundation
import Testing
@testable import LAICore
@Test func unsupportedEvidenceAndInventedFieldsAreDiscarded() throws {
    let segment=TranscriptSegment(sessionID:UUID(),source:.microphone,start:2,end:9,text:"Ana revisará el documento cuando esté listo.")
    let data=Data("""
    {"findings":[
    {"kind":"task","text":"Revisar el documento","segmentID":"\(segment.id)","quote":"Ana revisará el documento","owner":"Luis","due":"mañana"},
    {"kind":"decision","text":"Comprar equipos","segmentID":"missing","quote":"Comprar equipos"},
    {"kind":"decision","text":"Comprar equipos","segmentID":"\(segment.id)","quote":"Comprar equipos"}
    ]}
    """.utf8)
    let draft=try JSONDecoder().decode(DraftSummary.self,from:data)
    let findings=EvidenceValidator.validate(draft,segments:[segment],previous:[])
    #expect(findings.count==1); #expect(findings[0].owner==nil); #expect(findings[0].due==nil); #expect(findings[0].start==2)
}
@Test func summarySchemaCanBeConstructed() throws { _=try DraftSummary.schema() }
@Test func incompleteFindingDoesNotDiscardValidSiblings() throws {
    let segment=TranscriptSegment(sessionID:UUID(),source:.system,start:0,end:10,text:"Acordamos revisar el presupuesto del laboratorio.")
    let data=Data("""
    {"findings":[
      {"kind":"idea","segmentID":"\(segment.id)","quote":"revisar el presupuesto"},
      {"kind":"idea","text":17,"segmentID":"\(segment.id)","quote":"revisar el presupuesto"},
      null,
      {"kind":"decision","text":"Revisar el presupuesto.","segmentID":"\(segment.id)","quote":"Acordamos revisar el presupuesto"},
      {"kind":"task","text":"Comprar equipos","segmentID":"\(segment.id)"}
    ]}
    """.utf8)
    let draft=try DraftSummary.decodeResponse(data)
    let validated=EvidenceValidator.validate(draft,segments:[segment],previous:[])
    #expect(draft.findings.count==1)
    #expect(validated.count==1)
    #expect(validated.first?.kind == .decision)
    #expect(validated.first?.owner==nil)
    #expect(validated.first?.due==nil)
}
@Test func malformedSummaryExplainsRecoveryWithoutMissingDataMessage() throws {
    for json in ["{}", "{\"findings\":null}", "{\"findings\":[{\"kind\":\"idea\""] {
        do { _=try DraftSummary.decodeResponse(Data(json.utf8)); Issue.record("Malformed response was accepted") }
        catch let error as SummaryResponseError {
            #expect(error.localizedDescription.contains("resumen incompleto"))
            #expect(error.localizedDescription.contains("Actualizar resumen"))
        }
    }
    let empty=try DraftSummary.decodeResponse(Data("{\"findings\":[]}".utf8))
    #expect(empty.findings.isEmpty)
}
actor FixtureSummaryEngine:SummarizationEngine {
    var calls=0
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) -> [Finding] {
        calls += 1
        return EvidenceValidator.merge(previous:previous,new:segments.map { .init(kind:.idea,text:$0.text,segmentID:$0.id,quote:$0.text,start:$0.start,end:$0.end) })
    }
    func unload() {}
}
@Test func hierarchicalSummaryAdvancesCursorAndFinalizes() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory); let session=Session(title:"Larga",settings:AppSettings()); try await store.save(session)
    for i in 0..<40 { try await store.append(.init(sessionID:session.id,source:.system,start:Double(i),end:Double(i+1),text:"Tema \(i): "+String(repeating:"contenido ",count:40))) }
    let engine=FixtureSummaryEngine(); let coordinator=SummaryCoordinator(store:store)
    let first=try #require(try await coordinator.update(session:session,engine:engine,final:false)); #expect(!first.isFinal)
    let final=try #require(try await coordinator.update(session:session,engine:engine,final:true)); #expect(final.isFinal)
    let rows=try await store.segments(session:session.id)
    #expect(final.throughRow==rows.last?.0); #expect(await engine.calls>2)
    #expect(final.findings.count==40)
}

actor IncompleteSummaryEngine:SummarizationEngine {
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) throws -> [Finding] { throw SummaryResponseError.incomplete }
    func unload() {}
}
@Test func failedSummaryPreservesCheckpointAndCanBeRetried() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Recuperación",settings:AppSettings()); try await store.save(session)
    let coordinator=SummaryCoordinator(store:store)
    try await store.append(.init(sessionID:session.id,source:.system,start:0,end:10,text:"Revisamos el presupuesto del laboratorio."))
    let initial=try #require(try await coordinator.update(session:session,engine:FixtureSummaryEngine(),final:false))
    try await store.append(.init(sessionID:session.id,source:.system,start:10,end:20,text:"También revisamos el calendario de la próxima semana."))
    await #expect(throws:SummaryResponseError.self) {
        try await coordinator.update(session:session,engine:IncompleteSummaryEngine(),final:true)
    }
    let preserved=try #require(try await store.latestSummary(session:session.id))
    #expect(preserved.throughRow==initial.throughRow)
    #expect(preserved.findings==initial.findings)
    let recovered=try #require(try await coordinator.update(session:session,engine:FixtureSummaryEngine(),final:true))
    let rows=try await store.segments(session:session.id)
    #expect(recovered.throughRow==rows.last?.0)
    #expect(recovered.findings.count==2)
    #expect(recovered.isFinal)
}

@Test func duplicateEvidenceMergesRephrasedTasks() {
    let old=Finding(kind:.task,text:"Enviar cotización",segmentID:"system-0",quote:"Ana enviará la cotización",start:0,end:2)
    var revised=old; revised.text="Ana debe enviar la cotización"
    let merged=EvidenceValidator.merge(previous:[old],new:[revised])
    #expect(merged.count==1); #expect(merged[0].text==revised.text)
}
@Test func copyableMeetingReportPreservesEvidenceFields() {
    let session=Session(title:"Coordinación del laboratorio",settings:AppSettings())
    let findings:[Finding]=[
        .init(kind:.topic,text:"Compra de equipos",segmentID:"system-0",quote:"comprar dos micrófonos",start:0,end:1),
        .init(kind:.overview,text:"Se revisó el presupuesto y la compra de micrófonos.",segmentID:"system-0",quote:"revisamos el presupuesto",start:0,end:1),
        .init(kind:.idea,text:"Se necesitan dos micrófonos.",segmentID:"system-0",quote:"dos micrófonos",start:0,end:1),
        .init(kind:.task,text:"Enviar la cotización.",segmentID:"microphone-1",quote:"Ana enviará la cotización el viernes",start:1,end:2,owner:"Ana",due:"viernes")]
    let report=SessionReportFormatter.text(session:session,findings:findings)
    #expect(report.hasPrefix("Coordinación del laboratorio\n"))
    #expect(report.contains("Resumen general\n\nSe revisó el presupuesto"))
    #expect(report.contains("Puntos clave\n• Se necesitan dos micrófonos."))
    #expect(report.contains("Compromisos\nTarea | Responsable | Fecha\nEnviar la cotización. | Ana | viernes"))
    #expect(!report.contains("Evidencia:"))
    let empty=SessionReportFormatter.text(session:session,findings:[])
    #expect(empty.contains("El resumen todavía no está disponible."))
    #expect(!empty.contains("Compromisos"))
    #expect(!empty.contains("Responsable:"))
}
