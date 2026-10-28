import Foundation
import Testing
@testable import LAICore

private actor IdentifiedSummary:SummarizationEngine {
    let identity:String
    var calls=0
    init(_ identity:String) { self.identity=identity }
    func identifier() -> String? { identity }
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) -> [Finding] {
        calls += 1
        guard let segment=segments.first else { return previous }
        return [.init(kind:.overview,text:segment.text,segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end)]
    }
    func unload() {}
}
private actor ImportTestEngine:TranscriptionEngine {
    var id=UUID()
    var events:AsyncStream<PipelineEvent>.Continuation?
    var maximumSamples=0
    var seenSources=Set<AudioSource>()
    var chunks=0
    let failAfter:Int?
    init(failAfter:Int?=nil) { self.failAfter=failAfter }
    func start(sessionID:UUID,sources:[AudioSource],settings:AppSettings,events:AsyncStream<PipelineEvent>.Continuation) { id=sessionID; self.events=events }
    func append(_ chunk:AudioChunk) async throws {
        maximumSamples=max(maximumSamples,chunk.samples.count); seenSources.insert(chunk.source); chunks += 1
        if chunks==1,let events { try await SpeechEventDelivery.emit(.init(sessionID:id,source:.file,start:0,end:0.1,text:"Texto definitivo de prueba"),to:events) }
        if let failAfter,chunks>=failAfter { throw LAIError.message("Synthetic import failure") }
    }
    func finish() {}
    func cancel() {}
}

@Test(.timeLimit(.minutes(1))) func importClosesEventsWhenInitialSaveFails() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Invalid initial save",settings:AppSettings()); session.duration = .nan
    let pair=AsyncStream<PipelineEvent>.makeStream()
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    await #expect(throws:EncodingError.self) {
        _=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation,engineOverride:ImportTestEngine())
    }
    var events=0
    for await _ in pair.stream { events += 1 }
    #expect(events==0)
}

@Test func sessionContextIsBoundedStableAndBackwardsCompatible() throws {
    let context=SessionContext(objective:String(repeating:"o",count:300),agenda:String(repeating:"a",count:900),glossary:String(repeating:"g",count:700))
    #expect(context.bounded.objective.count==250); #expect(context.bounded.agenda.count==600); #expect(context.bounded.glossary.count==350)
    #expect(context.engineIdentifier(backend:"apple")==context.bounded.engineIdentifier(backend:"apple"))
    #expect(context.engineIdentifier(backend:"apple") != context.engineIdentifier(backend:"google"))
    var object=try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(Session(title:"Old",settings:AppSettings()))) as? [String:Any])
    object.removeValue(forKey:"context"); object.removeValue(forKey:"importedFileName")
    let old=try JSONDecoder().decode(Session.self,from:JSONSerialization.data(withJSONObject:object))
    #expect(old.context==nil); #expect(old.settings.googleEnabled != true)
}
@Test func executiveViewSelectsExistingFindingsWithoutChangingEvidence() {
    let facts:[Finding]=(0..<20).map { index in
        let kind:FindingKind
        if index==0 { kind = .overview }
        else if index==1 { kind = .idea }
        else { kind=index%2==0 ? .decision:.task }
        return Finding(kind:kind,text:"Punto \(index)",segmentID:"system-\(index)",quote:"Evidencia \(index)",start:Double(index),end:Double(index+1))
    }
    let selected=ReportPresentation.executive.select(facts)
    #expect(selected.first==facts.first); #expect(!selected.contains{$0.kind == .idea})
    #expect(selected.filter{$0.kind == .task}.count==5); #expect(selected.filter{$0.kind == .decision}.count==5)
    #expect(ReportPresentation.complete.select(facts)==facts)
    #expect(selected.allSatisfy{fact in facts.contains(fact)})
}
@Test func frequentTermsIgnoreAccentsPartialsAndEchoes() {
    let id=UUID()
    let first=TranscriptSegment(sessionID:id,source:.file,start:0,end:5,text:"Micrófonos, micrófonos y presupuesto. El presupuesto del laboratorio.")
    let partial=TranscriptSegment(sessionID:id,source:.file,start:6,end:7,text:"parcial parcial parcial",isFinal:false)
    var echo=first; echo.duplicateOf=first.id
    let ranked=SessionTerm.rank([first,partial,echo])
    #expect(ranked.contains(.init(text:"microfonos",count:2))); #expect(ranked.contains(.init(text:"presupuesto",count:2)))
    #expect(!ranked.contains{$0.text=="parcial" || $0.text=="laboratorio"})
}
@Test func progressUsesPersistedCursorAndBackendChangeRebuilds() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Cursor",settings:AppSettings())
    try await store.save(session)
    try await store.append(.init(sessionID:session.id,source:.file,start:0,end:5,text:"Acordamos comprar equipos para el laboratorio."))
    let coordinator=SummaryCoordinator(store:store),first=IdentifiedSummary("google:model:context")
    _=try await coordinator.update(session:session,engine:first,final:true)
    let stored=try await store.latestSummary(session:session.id)
    #expect(stored?.engineIdentifier=="google:model:context")
    try await store.append(.init(sessionID:session.id,source:.file,start:5,end:12,text:"Revisamos el presupuesto para los equipos."))
    let progress=try await store.processingProgress(session:session.id)
    #expect(progress.transcribedThrough==12); #expect(progress.summarizedThrough==5); #expect(progress.pendingSegments==1); #expect(!progress.isFinal)
    let second=IdentifiedSummary("apple::different-context")
    _=try await coordinator.update(session:session,engine:second,final:true)
    #expect(await second.calls==2)
    #expect(try await store.latestSummary(session:session.id)?.engineIdentifier=="apple::different-context")
}
@Test func audioImportPersistsFinalsAndBoundsPCMBuffers() async throws {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    let fixture=root.appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Imported",settings:AppSettings()),engine=ImportTestEngine()
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
    let completed=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation,engineOverride:engine)
    #expect(completed.status=="completed"); #expect(completed.duration>5); #expect(completed.importedFileName=="spanish-synthetic.aiff")
    #expect(await engine.maximumSamples<=4096); #expect(await engine.seenSources==[.file])
    #expect(try await store.segments(session:session.id).count==1)
    #expect(try await store.segments(session:session.id,search:"DEFINITÍVO").count==1)
    #expect(!FileManager.default.fileExists(atPath:directory.appendingPathComponent(session.id.uuidString).path))
}
@Test func interruptedImportPreservesAlreadyRecognizedText() async throws {
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Interrupted import",settings:AppSettings()),engine=ImportTestEngine(failAfter:8)
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
    do { _=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation,engineOverride:engine); Issue.record("Failure accepted") } catch {}
    #expect(try await store.session(id:session.id)?.status=="interrupted")
    #expect(try await store.segments(session:session.id).count==1)
}
@Test(.enabled(if:ProcessInfo.processInfo.environment["PAIMON_TEST_NATIVE_IMPORT"]=="1"),.timeLimit(.minutes(1))) func nativeAudioImportProducesRealSpanishText() async throws {
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Native import",settings:AppSettings())
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
    _=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation)
    let text=try await store.segments(session:session.id).map{$0.1.text}.joined(separator:" ").lowercased()
    #expect(text.contains("micrófonos")); #expect(text.contains("cotización")); #expect(text.contains("viernes"))
}
