import Foundation
import Testing
import FoundationModels
@testable import LAICore

@Test(.enabled(if:ProcessInfo.processInfo.environment["PAIMON_TEST_DISCOURSE"]=="1"),.timeLimit(.minutes(3)))
func discourseNativeDenseSourcesKeepGroundedResultsAndCompleteCheckpoint() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("paimon-discourse-dense-\(UUID())")
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Discurso sintético denso",settings:AppSettings());session.status="completed"
    try await store.save(session)
    let texts=[
        "Propongo crear un catálogo digital de la biblioteca porque los estudiantes necesitan consultar la disponibilidad de libros.",
        "El catálogo es como un mapa: permite localizar recursos. Por ejemplo, un estudiante podría encontrar el manual de física.",
        "Me opongo a comprar equipos todavía porque no conocemos el presupuesto. ¿Cuánto costaría reparar los microscopios?",
        "La reparación de los microscopios cuesta dos millones de pesos. Este monto responde la pregunta sobre el coste de reparar los equipos.",
        "Propongo un calendario compartido para reservar salas porque evitaría reservas duplicadas. Falta decidir qué herramienta utilizar.",
        "Mantenemos la propuesta del calendario compartido. Cambiamos el calendario de reservas para incluir los talleres de formación.",
        "Un catálogo digital es un registro consultable de libros y sus ubicaciones. La formación del personal explicará cómo actualizarlo.",
        "Quizás convenga probar primero el catálogo digital en una biblioteca. No sabemos todavía cuánto durará esa prueba."
    ]
    for (i,text) in texts.enumerated() {
        try await store.append(.init(sessionID:session.id,source:.file,start:Double(i*15),end:Double(i*15+12),text:text))
    }
    try await DiscourseAnalyzer.analyze(session:session,store:store,final:true)
    let state=try #require(try await store.discourseState(session:session.id))
    let findings=try await store.discourseFindings(session:session.id)
    #expect(state.final)
    #expect(try await state.through==store.lastTranscriptRow(session:session.id))
    #expect(findings.isEmpty==false)
    #expect(findings.allSatisfy{ finding in finding.evidence.allSatisfy{ reference in texts.contains{ $0.contains(reference.quote) } } })
}

private actor ScriptedDiscourseGenerator:DiscourseGenerating {
    enum Failure:Sendable { case none,first,later,cancel,provider }
    let failure:Failure
    let maximumSources:Int
    private(set) var calls:[(sources:Int,compact:Bool,prior:Int)]=[]
    init(_ failure:Failure = .none,maximumSources:Int=4) { self.failure=failure;self.maximumSources=maximumSources }
    nonisolated func availability(locale:String) -> String? { nil }
    func fits(prompt:String,compact:Bool) throws -> Bool {
        let object=try JSONSerialization.jsonObject(with:Data(prompt.utf8)) as! [String:Any]
        return (object["CURRENT"] as! [[String:String]]).count <= maximumSources
    }
    func generate(prompt:String,compact:Bool) throws -> DiscourseDraft {
        let object=try JSONSerialization.jsonObject(with:Data(prompt.utf8)) as! [String:Any]
        let rows=object["CURRENT"] as! [[String:String]]
        calls.append((rows.count,compact,(object["PRIOR"] as! [[String:String]]).count))
        if failure == .cancel { throw CancellationError() }
        if failure == .provider { throw LAIError.message("Synthetic provider failure") }
        if (failure == .first && calls.count==1) || (failure == .later && calls.count>1) {
            let item:[String:Any]=["citations":[["source":"F1","quote":rows[0]["text"]!]],"kind":"proposal","statement":"Propuesta documentada","topic":"Biblioteca","parentTopic":""]
            let json=try JSONSerialization.data(withJSONObject:["items":[item]])
            return try DiscourseDraft(GeneratedContent(json:String(decoding:json,as:UTF8.self)))
        }
        return .init(items:rows.prefix(compact ? 2:4).map { row in
            .init(citations:[.init(source:DiscourseSourceKey(rawValue:row["key"]!)!,quote:String(row["text"]!.prefix(100)))],kind:.proposal,
                  statement:"Propuesta documentada",topic:"Plan de biblioteca",parentTopic:"",target:.none)
        })
    }
}

private struct DiscourseFixture {
    let directory:URL
    let store:SessionStore
    let session:Session
    init() async throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("paimon-discourse-recovery-\(UUID())")
        store=try SessionStore(directory:directory)
        var value=Session(title:"Discurso controlado",settings:AppSettings());value.status="completed";session=value
        try await store.save(session)
    }
    func append(_ count:Int) async throws {
        for i in 0..<count { try await store.append(.init(sessionID:session.id,source:.file,start:Double(i*10),end:Double(i*10+8),text:"Propongo revisar el catálogo de biblioteca en la etapa \(i).")) }
    }
    func clean() { try? FileManager.default.removeItem(at:directory) }
}

@Test func discourseRecoveryShrinksTheRetryWithoutSkippingRemainingSources() async throws {
    let fixture=try await DiscourseFixture();defer{fixture.clean()};try await fixture.append(6)
    let generator=ScriptedDiscourseGenerator(.first)
    try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:generator)
    let calls=await generator.calls
    #expect(calls.map(\.sources)==[4,2,4])
    #expect(calls.map(\.compact)==[false,true,false])
    #expect(try await fixture.store.discourseFindings(session:fixture.session.id).count==6)
    let state=try #require(try await fixture.store.discourseState(session:fixture.session.id))
    #expect(state.final)
    #expect(try await state.through==fixture.store.lastTranscriptRow(session:fixture.session.id))
}

@Test func discoursePermanentFailureRetainsCheckpointAndResumesOnlyThePendingSources() async throws {
    let fixture=try await DiscourseFixture();defer{fixture.clean()};try await fixture.append(6)
    let generator=ScriptedDiscourseGenerator(.later)
    do {
        try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:generator)
        Issue.record("Expected incomplete discourse response")
    } catch let error as DiscourseResponseError {
        guard case .incomplete=error else { Issue.record("Wrong discourse error");return }
        #expect(error.localizedDescription.contains("avance guardado"))
    }
    let partial=try #require(try await fixture.store.discourseState(session:fixture.session.id))
    #expect(partial.through==4 && partial.final==false)
    let retained=try await fixture.store.discourseFindings(session:fixture.session.id)
    #expect(retained.count==4)
    #expect(await generator.calls.count==3)
    let retry=ScriptedDiscourseGenerator()
    try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:retry)
    let all=try await fixture.store.discourseFindings(session:fixture.session.id)
    #expect(all.count==6)
    #expect(Set(retained.map(\.id)).isSubset(of:Set(all.map(\.id))))
    #expect(await retry.calls.map(\.sources)==[2])
    #expect(await retry.calls.first?.prior==4)
    #expect(try await fixture.store.discourseState(session:fixture.session.id)?.final==true)
}

@Test(arguments:[false,true])
func discourseCancellationAndProviderErrorsDoNotTriggerParsingRetries(_ cancelled:Bool) async throws {
    let fixture=try await DiscourseFixture();defer{fixture.clean()};try await fixture.append(2)
    let generator=ScriptedDiscourseGenerator(cancelled ? .cancel:.provider)
    do {
        try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:generator)
        Issue.record("Expected the original failure")
    } catch {
        #expect(cancelled ? error is CancellationError:error is LAIError)
    }
    #expect(await generator.calls.count==1)
    #expect(try await fixture.store.discourseState(session:fixture.session.id)==nil)
}

@Test func discourseContextBudgetConsumesOnlySourcesThatFit() async throws {
    let fixture=try await DiscourseFixture();defer{fixture.clean()};try await fixture.append(6)
    let generator=ScriptedDiscourseGenerator(maximumSources:1)
    try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:generator)
    #expect(await generator.calls.map(\.sources)==Array(repeating:1,count:6))
    #expect(try await fixture.store.discourseFindings(session:fixture.session.id).count==6)
    #expect(try await fixture.store.discourseState(session:fixture.session.id)?.final==true)
}

@Test func discourseSplitSegmentDoesNotAdvanceUntilItsLastPartCommits() async throws {
    let fixture=try await DiscourseFixture();defer{fixture.clean()}
    let text=String(repeating:"Propongo revisar el catálogo de biblioteca y ordenar sus registros. ",count:35)
    try await fixture.store.append(.init(sessionID:fixture.session.id,source:.file,start:0,end:60,text:text))
    await #expect(throws:DiscourseResponseError.self) {
        try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:ScriptedDiscourseGenerator(.later,maximumSources:1))
    }
    #expect(try await fixture.store.discourseState(session:fixture.session.id)?.through==0)
    #expect(try await fixture.store.discourseState(session:fixture.session.id)?.final==false)
    let before=try await fixture.store.discourseFindings(session:fixture.session.id)
    try await DiscourseAnalyzer.analyze(session:fixture.session,store:fixture.store,final:true,generator:ScriptedDiscourseGenerator(maximumSources:1))
    #expect(try await fixture.store.discourseState(session:fixture.session.id)?.final==true)
    #expect(try await fixture.store.discourseState(session:fixture.session.id)?.through==fixture.store.lastTranscriptRow(session:fixture.session.id))
    let after=try await fixture.store.discourseFindings(session:fixture.session.id)
    #expect(Set(before.map(\.id)).isSubset(of:Set(after.map(\.id))))
    #expect(Set(after.map(\.id)).count==after.count)
}
