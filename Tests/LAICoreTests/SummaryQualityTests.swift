import Foundation
import Testing
import PDFKit
@testable import LAICore

@Test func overviewCannotInventAnApprovalDisclaimer() throws {
    let source=SummarySource(TranscriptSegment(sessionID:UUID(),source:.file,start:0,end:8,text:"Acordamos comprar dos micrófonos. Ana enviará la cotización el viernes."))
    let bad=try JSONDecoder().decode(GroundedSummary.self,from:Data("""
    {"title":"Micrófonos","overview":"Se acordó comprar dos micrófonos. Estas propuestas no tienen aprobación explícita."}
    """.utf8))
    #expect(throws:SummaryResponseError.self) { try SummaryGrounding.validate(bad,sources:[source],maximumPoints:0) }
    let good=try JSONDecoder().decode(GroundedSummary.self,from:Data("""
    {"title":"Micrófonos","overview":"Se acordó comprar dos micrófonos y Ana enviará la cotización el viernes."}
    """.utf8))
    #expect(try SummaryGrounding.validate(good,sources:[source],maximumPoints:0).contains{$0.kind == .overview})
}

@Test func pendingDecisionCannotBorrowAnAgreementFromAnotherSentence() throws {
    let segment=TranscriptSegment(sessionID:UUID(),source:.system,start:0,end:11,text:"Hoy revisamos el presupuesto del laboratorio. Acordamos comprar dos micrófonos. Ana enviará la cotización el viernes. Falta decidir dónde instalar los equipos.")
    let source=SummarySource(segment)
    #expect(SummaryGrounding.finding(kind:.decision,text:"Decidir dónde instalar los equipos",sources:[source])==nil)
    #expect(SummaryGrounding.finding(kind:.decision,text:"Comprar dos micrófonos",sources:[source]) != nil)
    #expect(SummaryGrounding.finding(kind:.question,text:"Falta decidir dónde instalar los equipos",sources:[source]) != nil)
    let json="""
    {"findings":[
    {"kind":"decision","text":"Decidir dónde instalar los equipos","segmentID":"\(segment.id)","quote":"\(segment.text)"},
    {"kind":"decision","text":"Comprar dos micrófonos","segmentID":"\(segment.id)","quote":"\(segment.text)"}
    ]}
    """
    let legacy=EvidenceValidator.validate(try DraftSummary.decodeResponse(Data(json.utf8)),segments:[segment],previous:[])
    #expect(legacy.map(\.text)==["Comprar dos micrófonos"])
}
@Test func pendingEnglishDecisionCannotBorrowAnAgreementFromAnotherSentence() {
    let quote="We agreed to buy two microphones. We still need to decide where to install the equipment."
    #expect(SummaryGrounding.supportsDecision("Buy two microphones",quote:quote))
    #expect(!SummaryGrounding.supportsDecision("Decide where to install the equipment",quote:quote))
}

@Test func unrelatedIntroCannotBackAClaim() throws {
    let segment=TranscriptSegment(sessionID:UUID(),source:.system,start:377,end:379,text:"Bien, en el área de producción")
    let json="""
    {"findings":[{"kind":"idea","text":"Se destaca la importancia de escuchar propuestas de áreas clave","segmentID":"\(segment.id)","quote":"Bien, en el área de producción"}]}
    """
    #expect(EvidenceValidator.validate(try DraftSummary.decodeResponse(Data(json.utf8)),segments:[segment],previous:[]).isEmpty)
    #expect(!SummaryGrounding.informative(segment.text))
    #expect(SummaryGrounding.informative("Acordamos revisar el presupuesto."))
}
@Test func groundedSchemaRequiresAnOverviewAndUsesKnownAliases() throws {
    _=try GroundedSummary.schema(sourceCount:1,maximumPoints:4)
    _=try GroundedSummary.schema(sourceCount:8,maximumPoints:0)
    #expect(throws:DecodingError.self) { try JSONDecoder().decode(GroundedSummary.self,from:Data("{\"title\":\"Solo un título\",\"points\":[]}".utf8)) }
    let source=SummarySource(TranscriptSegment(sessionID:UUID(),source:.file,start:0,end:4,text:"La biblioteca incorporará un catálogo digital para consultar sus libros."))
    let draft=try JSONDecoder().decode(GroundedSummary.self,from:Data("{\"title\":\"Biblioteca digital\",\"overview\":\"Solo un título\"}".utf8))
    #expect(throws:SummaryResponseError.self) { try SummaryGrounding.validate(draft,sources:[source],maximumPoints:0) }
}
@Test func sourceQuotesAreResolvedLocallyAndAllOverviewReferencesSurviveExports() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Biblioteca",settings:AppSettings()); try await store.save(session)
    let a=TranscriptSegment(sessionID:session.id,source:.system,start:0,end:10,text:"La biblioteca incorporará un catálogo digital para consultar libros.")
    let b=TranscriptSegment(sessionID:session.id,source:.system,start:40,end:55,text:"La formación del personal incluirá talleres para utilizar el catálogo.")
    try await store.append(a); try await store.append(b)
    let data=Data("""
    {"title":"Catálogo de la biblioteca","overview":"La biblioteca incorporará un catálogo digital y organizará talleres para formar al personal.","points":[
    {"kind":"idea","text":"La biblioteca incorporará un catálogo digital.","sources":["S0"]},
    {"kind":"task","text":"Formación del personal en el catálogo.","sources":["S1"],"owner":"Persona inventada","due":"mañana"},
    {"kind":"idea","text":"El catálogo permitirá consultar libros.","sources":["S99"]}
    ]}
    """.utf8)
    let draft=try JSONDecoder().decode(GroundedSummary.self,from:data)
    let findings=try SummaryGrounding.validate(draft,sources:[SummarySource(a),SummarySource(b)],maximumPoints:4)
    let overview=try #require(findings.first{$0.kind == .overview})
    #expect(overview.evidence.map(\.quote)==[a.text,b.text])
    #expect(findings.filter{$0.kind == .idea}.count==1)
    #expect(findings.first{$0.kind == .task}?.owner==nil)
    #expect(findings.first{$0.kind == .task}?.due==nil)
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:2,isFinal:true,findings:findings,processingVersion:2))
    var options=ExportOptions(); options.transcript=false
    for format in ExportFormat.allCases {
        let url=directory.appendingPathComponent("report.\(format.rawValue)")
        try await SessionExporter(store:store).export(session:session,to:url,format:format,options:options)
        let text=format == .pdf ? PDFDocument(url:url)?.string ?? "":try String(contentsOf:url,encoding:.utf8)
        #expect(text.contains(a.text)); #expect(text.contains(b.text))
    }
}
actor QualityFixtureEngine:SummarizationEngine {
    enum Mode:Sendable { case complete, titleOnly, invalidFinal }
    let mode:Mode
    var sourceCalls=0
    init(_ mode:Mode = .complete) { self.mode=mode }
    nonisolated func processingVersion() -> Int { 2 }
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) -> [Finding] {
        if segments.isEmpty { return mode == .invalidFinal ? previous.filter{$0.kind != .overview}:previous }
        sourceCalls += 1
        guard let segment=segments.first else { return previous }
        let kind:FindingKind=mode == .titleOnly ? .topic:.overview
        let overview=Finding(kind:kind,text:segment.text,segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end)
        let idea=Finding(kind:.idea,text:segment.text,segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end)
        return mode == .titleOnly ? [overview]:[overview,idea]
    }
    func unload() {}
}
@Test func titleOnlyDoesNotAdvanceSummaryCursor() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Calidad",settings:AppSettings()); try await store.save(session)
    try await store.append(.init(sessionID:session.id,source:.system,start:0,end:10,text:"La biblioteca incorporará un catálogo digital para consultar los libros."))
    await #expect(throws:SummaryResponseError.self) { try await SummaryCoordinator(store:store).update(session:session,engine:QualityFixtureEngine(.titleOnly),final:true) }
    #expect(try await store.latestSummary(session:session.id)==nil)
}
@Test func oldSummaryVersionRebuildsTheOriginalOnce() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Anterior",settings:AppSettings()); try await store.save(session)
    let segment=TranscriptSegment(sessionID:session.id,source:.system,start:0,end:10,text:"La biblioteca incorporará un catálogo digital para consultar libros.")
    try await store.append(segment)
    let last=try #require(try await store.segments(session:session.id).last?.0)
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:last,isFinal:true,findings:[.init(kind:.topic,text:"Biblioteca",segmentID:segment.id,quote:segment.text,start:0,end:10)]))
    let coordinator=SummaryCoordinator(store:store),engine=QualityFixtureEngine()
    let fixed=try #require(try await coordinator.update(session:session,engine:engine,final:true))
    #expect(fixed.processingVersion==2); #expect(fixed.findings.contains{$0.kind == .overview})
    _=try await coordinator.update(session:session,engine:engine,final:false)
    #expect(await engine.sourceCalls==1)
    #expect(try await store.segments(session:session.id).count==1)
}
@Test func finalWithoutOverviewStaysPartialAndEarlierPointsArePreserved() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Acumulación",settings:AppSettings()); try await store.save(session)
    for i in 0..<3 {
        try await store.append(.init(sessionID:session.id,source:.system,start:Double(i*30),end:Double(i*30+20),text:"Biblioteca etapa \(i): "+String(repeating:"catálogo digital para consultar libros ",count:45)))
    }
    let coordinator=SummaryCoordinator(store:store)
    await #expect(throws:SummaryResponseError.self) { try await coordinator.update(session:session,engine:QualityFixtureEngine(.invalidFinal),final:true) }
    let partial=try #require(try await store.latestSummary(session:session.id))
    #expect(!partial.isFinal); #expect(partial.findings.filter{$0.kind == .idea}.count==3)
    let fixed=try #require(try await coordinator.update(session:session,engine:QualityFixtureEngine(),final:true))
    #expect(fixed.isFinal); #expect(fixed.findings.filter{$0.kind == .idea}.count==3)
}
@Test func legacyFindingsDecodeWithTheirPrimaryEvidence() throws {
    let data=Data("""
    {"id":"00000000-0000-0000-0000-000000000001","kind":"idea","text":"Catálogo digital","segmentID":"system-0","quote":"catálogo digital","start":0,"end":3}
    """.utf8)
    let finding=try JSONDecoder().decode(Finding.self,from:data)
    #expect(finding.additionalEvidence==nil); #expect(finding.evidence.count==1)
}
@Test func differentPointsCanShareASourceAndPunctuationDoesNotDuplicateThem() {
    let quote="El catálogo permite consultar libros. Los talleres forman al personal."
    let a=Finding(kind:.idea,text:"El catálogo permite consultar libros",segmentID:"system-0",quote:quote,start:0,end:10)
    let b=Finding(kind:.idea,text:"Los talleres forman al personal",segmentID:"system-0",quote:quote,start:0,end:10)
    var duplicate=a; duplicate.text += "."; duplicate.quote += "."
    let merged=EvidenceValidator.merge(previous:[a,b],new:[duplicate])
    #expect(merged.count==2)
    #expect(merged.contains{$0.text==b.text})
}
@Test func integratedOverviewDoesNotCiteUnrelatedGreetingsOrMicrophoneProblems() {
    let id=UUID()
    let sources=[
        TranscriptSegment(sessionID:id,source:.system,start:0,end:10,text:"La biblioteca propone un catálogo digital para consultar libros."),
        TranscriptSegment(sessionID:id,source:.system,start:20,end:25,text:"Buenas noches, mi nombre es Elena y me presento ante ustedes."),
        TranscriptSegment(sessionID:id,source:.system,start:40,end:45,text:"Tienes el micrófono apagado y no podemos escuchar tu voz.")
    ].map(SummarySource.init)
    let finding=SummaryGrounding.finding(kind:.overview,text:"La biblioteca propone un catálogo digital para facilitar la consulta de libros.",sources:sources)
    #expect(finding?.evidence.count==1)
    #expect(finding?.evidence.first?.start==0)
}
