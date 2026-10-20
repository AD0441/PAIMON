import Foundation
import Testing
import CSQLite
import PDFKit
@testable import LAICore

private actor TestLatch {
    private var open=false
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func wait() async { if !open { await withCheckedContinuation { waiters.append($0) } } }
    func release() { open=true; for waiter in waiters { waiter.resume() }; waiters=[] }
}
private actor CoordinatedEngine:SummarizationEngine {
    let started:TestLatch
    let release:TestLatch
    let byteLimit:Int
    var sourceCalls=0,finalCalls=0,inFlight=0,maximumConcurrent=0
    var finalContext:[Finding]=[]
    init(started:TestLatch=TestLatch(),release:TestLatch=TestLatch(),byteLimit:Int=Int.max) { self.started=started; self.release=release; self.byteLimit=byteLimit }
    nonisolated func processingVersion() -> Int { 2 }
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        inFlight += 1; maximumConcurrent=max(maximumConcurrent,inFlight); defer { inFlight -= 1 }
        if segments.isEmpty { finalCalls += 1; finalContext=previous; return previous }
        sourceCalls += 1
        if sourceCalls==1 { await started.release(); await release.wait() }
        try Task.checkCancellation()
        if segments.reduce(0,{$0+$1.text.utf8.count})>byteLimit { throw SummaryContextError.exceeded }
        let fresh=segments.flatMap { segment in
            [Finding(kind:.overview,text:segment.text,segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end),Finding(kind:.decision,text:segment.text,segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end)]
        }
        return EvidenceValidator.merge(previous:previous,new:fresh)
    }
    func unload() {}
}
private func fixtureStore() throws -> (URL,SessionStore,Session) {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return (directory,try SessionStore(directory:directory),Session(title:"Prueba sintética",settings:AppSettings()))
}
private func segment(_ session:Session,_ index:Int) -> TranscriptSegment {
    .init(sessionID:session.id,source:.system,start:Double(index*10),end:Double(index*10+8),text:"Acordamos revisar el presupuesto del laboratorio en la etapa \(index).")
}

@Test(.timeLimit(.minutes(1))) func stopDuringManualSummaryProcessesTailAndFinalizesOnce() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session); try await store.append(segment(session,0))
    let started=TestLatch(),release=TestLatch(),coordinator=SummaryCoordinator(store:store)
    let engine=CoordinatedEngine(started:started,release:release)
    let manual=Task { try await coordinator.update(session:session,engine:engine,final:false) }
    await started.wait()
    // This represents the final ASR tail being persisted before Stop requests finalization.
    try await store.append(segment(session,1))
    let stop=Task { try await coordinator.update(session:session,engine:engine,final:true) }
    await release.release(); _=try await manual.value
    let final=try #require(try await stop.value)
    let watermark=try await store.segments(session:session.id,limit:1,newest:true).last?.0
    #expect(final.isFinal); #expect(final.throughRow==watermark)
    #expect(await engine.maximumConcurrent==1); #expect(await engine.finalCalls==1)
    let duplicate=try await coordinator.update(session:session,engine:engine,final:true)
    #expect(duplicate==nil); #expect(await engine.finalCalls==1)
}

@Test(.timeLimit(.minutes(1))) func queuedCancellationDoesNotWaitForActiveInference() async throws {
    let gate=InferenceGate(),started=TestLatch(),release=TestLatch(),queued=TestLatch()
    let first=Task { try await gate.perform { await started.release(); await release.wait(); return 1 } }
    await started.wait()
    let second=Task { await queued.release(); return try await gate.perform { 2 } }
    await queued.wait(); second.cancel()
    do { _=try await second.value; Issue.record("Cancelled queue entry ran") } catch is CancellationError {}
    // Still blocked here: cancellation completed without releasing first.
    await release.release(); #expect(try await first.value==1)
    #expect(try await gate.perform { 3 }==3)
}

@Test(.timeLimit(.minutes(1))) func coordinatorCancellationRetainsCheckpointAndAllowsRecovery() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session); try await store.append(segment(session,0))
    let started=TestLatch(),release=TestLatch(),coordinator=SummaryCoordinator(store:store)
    let engine=CoordinatedEngine(started:started,release:release)
    let active=Task { try await coordinator.update(session:session,engine:engine,final:false) }
    await started.wait(); active.cancel()
    do { _=try await active.value; Issue.record("Cancelled request completed") } catch is CancellationError {}
    await release.release()
    #expect(try await store.latestSummary(session:session.id)==nil)
    let recovered=try #require(try await coordinator.update(session:session,engine:engine,final:true))
    #expect(recovered.isFinal); #expect(recovered.throughRow>0)
}

@Test func contextOverflowSplitsWithoutAdvancingPastFailedContent() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session)
    for index in 0..<20 { try await store.append(segment(session,index)) }
    let release=TestLatch(); await release.release()
    let engine=CoordinatedEngine(release:release,byteLimit:180)
    let result=try #require(try await SummaryCoordinator(store:store).update(session:session,engine:engine,final:true))
    #expect(result.isFinal)
    #expect(try await store.findings(session:session.id,template:.meeting).count==20)
    let metrics=try #require(try await store.summaryMetrics(session:session.id).first)
    #expect(metrics.contextReductions>0); #expect(metrics.outcome=="completed")
}

@Test func durableRegisterKeepsOldDecisionsBeyondWorkingMemoryAndAcrossExports() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session)
    for index in 0..<160 { try await store.append(segment(session,index)) }
    let release=TestLatch(); await release.release()
    let engine=CoordinatedEngine(release:release)
    let snapshot=try #require(try await SummaryCoordinator(store:store).update(session:session,engine:engine,final:true))
    #expect(snapshot.findings.count<=80)
    #expect(try await store.findings(session:session.id,template:.meeting,limit:200).count==160)
    #expect(await engine.finalContext.contains{$0.kind == .decision && $0.start==0})
    let reopened=try SessionStore(directory:directory)
    #expect(try await reopened.findings(session:session.id,template:.meeting,limit:200).count==160)
    for format in ExportFormat.allCases {
        var options=ExportOptions(); options.transcript=false
        let url=directory.appendingPathComponent("register.\(format.rawValue)")
        try await SessionExporter(store:store).export(session:session,to:url,format:format,options:options)
        let data=try Data(contentsOf:url)
        if format == .json {
            let json=try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
            #expect((json["findings"] as? [[String:Any]])?.filter{$0["kind"] as? String=="decision"}.count==160)
        } else {
            let text=format == .pdf ? PDFDocument(data:data)?.string ?? "":String(decoding:data,as:UTF8.self)
            #expect(text.contains("etapa 0")); #expect(text.contains("etapa 159"))
            if format == .markdown {
                #expect(text.contains("**")); #expect(text.components(separatedBy:"# Prueba sintética\n").count==2)
                #expect(text.components(separatedBy:"## Evidencias\n").count==2)
                let lastDecision=try #require(text.range(of:"etapa 159")),annex=try #require(text.range(of:"## Evidencias"))
                #expect(lastDecision.lowerBound<annex.lowerBound)
            }
        }
    }
    try await store.delete(session:session.id)
    #expect(try await store.findings(session:session.id,template:.meeting).isEmpty)
    #expect(try await store.summaryMetrics(session:session.id).isEmpty)
}

@Test(.timeLimit(.minutes(1))) func repeatedQueuedUpdatesCoalesceAndKeepTheFinalRequest() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session); try await store.append(segment(session,0))
    let started=TestLatch(),release=TestLatch(),coordinator=SummaryCoordinator(store:store)
    let engine=CoordinatedEngine(started:started,release:release)
    let first=Task { try await coordinator.update(session:session,engine:engine,final:false) }
    await started.wait()
    let requests=(0..<12).map { index in Task { try await coordinator.update(session:session,engine:engine,final:index==11) } }
    while await coordinator.queuedRequests<12 { await Task.yield() }
    await release.release(); _=try await first.value
    for request in requests { _=try await request.value }
    #expect(await engine.sourceCalls==1); #expect(await engine.finalCalls==1)
    #expect(try await store.latestSummary(session:session.id)?.isFinal==true)
}

@Test func historicalFactMigrationIsResumableAndDoesNotRestoreAnotherTemplate() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session)
    // Build an old v2 database through raw SQLite, with no imported-fact markers.
    var db:OpaquePointer?; #expect(sqlite3_open(directory.appendingPathComponent("sessions.sqlite").path,&db)==SQLITE_OK)
    defer { sqlite3_close(db) }
    for index in 0..<25 {
        let source=segment(session,index)
        let finding=Finding(kind:.decision,text:source.text,segmentID:source.id,quote:source.text,start:source.start,end:source.end)
        let snapshot=SummarySnapshot(sessionID:session.id,throughRow:Int64(index),isFinal:false,findings:[finding],template:.meeting)
        let json=String(decoding:try JSONEncoder().encode(snapshot),as:UTF8.self).replacingOccurrences(of:"'",with:"''")
        #expect(sqlite3_exec(db,"INSERT INTO summaries(session,data) VALUES('\(session.id.uuidString)','\(json)')",nil,nil,nil)==SQLITE_OK)
    }
    #expect(try await !store.indexNextFindingBatch(session:session.id,limit:2))
    let reopened=try SessionStore(directory:directory)
    while try await !reopened.indexNextFindingBatch(session:session.id,limit:3) {}
    #expect(try await reopened.findings(session:session.id,template:.meeting).count==25)
    #expect(try await reopened.findings(session:session.id,template:.lecture).isEmpty)
}

@Test func schedulingDefersPressureAndSilenceButRespondsToVolume() {
    #expect(!SummarySchedule.shouldUpdate(pending:.init(),secondsSinceUpdate:900,interval:300,underPressure:false))
    #expect(!SummarySchedule.shouldUpdate(pending:.init(segments:20,bytes:9000),secondsSinceUpdate:900,interval:300,underPressure:true))
    #expect(SummarySchedule.shouldUpdate(pending:.init(segments:20,bytes:9000),secondsSinceUpdate:65,interval:300,underPressure:false))
    #expect(!SummarySchedule.shouldUpdate(pending:.init(segments:1,bytes:100),secondsSinceUpdate:65,interval:300,underPressure:false))
    #expect(SummarySchedule.shouldUpdate(pending:.init(segments:1,bytes:100),secondsSinceUpdate:300,interval:300,underPressure:false))
}

@Test func partialPresentationIsBoundedAndNeverReintroducesFinalizedText() {
    var buffer=LiveDisplayBuffer(); let session=Session(title:"Pantalla",settings:AppSettings())
    for index in 0..<10_000 { var value=segment(session,index); value.isFinal=false; buffer.partial(value); buffer.activity(.system,level:0.1,active:true) }
    #expect(buffer.partials.count==1); #expect(buffer.partials[.system]?.start==99990)
    buffer.finalized(.system); let flushed=buffer.drain()
    #expect(flushed.partials.isEmpty); #expect(flushed.voice[.system]==true); #expect(buffer.levels.isEmpty)
}

@Test func historyPagesStayBoundedAndSupportUnicodeSearch() async throws {
    let (directory,store,_)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    for index in 0..<121 { var value=Session(title:index%2==0 ? "Revisión CAFÉ":"Revisión té",settings:AppSettings()); value.created=Date(timeIntervalSince1970:Double(index)); try await store.save(value) }
    let first=try await store.sessions(),second=try await store.sessions(offset:50),last=try await store.sessions(offset:100)
    #expect(first.count==50); #expect(second.count==50); #expect(last.count==21)
    #expect(Set(first.map(\.id)).isDisjoint(with:Set(second.map(\.id))))
    #expect(try await store.sessions(search:"café",limit:200).count==61)
}

@Test(.timeLimit(.minutes(1))) func finalizedSpeechWaitsForPersistenceCapacityOrReportsFailure() async throws {
    let session=Session(title:"Entrega",settings:AppSettings())
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingOldest(1))
    pair.continuation.yield(.segment(segment(session,0)))
    // No consumer can free capacity in this branch; failure must be explicit.
    await #expect(throws:LAIError.self) { try await SpeechEventDelivery.emit(segment(session,1),to:pair.continuation,timeout:.milliseconds(60)) }
    let delivery=Task { try await SpeechEventDelivery.emit(segment(session,2),to:pair.continuation) }
    var iterator=pair.stream.makeAsyncIterator()
    _=await iterator.next()
    try await delivery.value
    if case .segment(let final)=await iterator.next() { #expect(final.start==20) } else { Issue.record("Final text was lost") }
    pair.continuation.finish()
}

@Test func identicalTaskWordingDoesNotEraseDifferentExplicitOwnersOrDates() {
    let a=Finding(kind:.task,text:"Enviar cotización",segmentID:"system-0",quote:"Ana enviará la cotización el lunes y Luis el viernes",start:0,end:10,owner:"Ana",due:"lunes")
    var b=a; b.id=UUID(); b.owner="Luis"; b.due="viernes"
    #expect(EvidenceValidator.merge(previous:[a],new:[b]).count==2)
}

@Test func finalJobsSurviveRelaunchAndCompleteWithTheSnapshotTransaction() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session); try await store.requestFinalSummary(session:session.id)
    let reopened=try SessionStore(directory:directory)
    #expect(try await reopened.pendingFinalSession()?.id==session.id)
    try await reopened.save(SummarySnapshot(sessionID:session.id,throughRow:0,isFinal:false,findings:[]))
    #expect(try await store.pendingFinalSession()?.id==session.id)
    try await reopened.save(SummarySnapshot(sessionID:session.id,throughRow:0,isFinal:true,findings:[]))
    #expect(try await store.pendingFinalSession()==nil)
    try await store.requestFinalSummary(session:session.id); try await store.delete(session:session.id)
    #expect(try await reopened.pendingFinalSession()==nil)
}

@Test func ledgerRevisionsPreferNewerSnapshotsAndPreserveEarlierFacts() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session)
    let source=segment(session,0)
    let first=Finding(kind:.decision,text:"Revisar presupuesto",segmentID:source.id,quote:source.text,start:0,end:8)
    var revised=first; revised.id=UUID(); revised.text="Revisar el presupuesto."
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:1,isFinal:false,findings:[first]))
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:1,isFinal:true,findings:[revised]))
    let values=try await store.findings(session:session.id,template:.meeting)
    #expect(values.count==1); #expect(values.first?.text==revised.text)
}

@Test func interruptedValidationRestoresTheOriginalSettingsOnNextLoad() throws {
    let suite="paimon-settings-test-\(UUID())",defaults=try #require(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    var original=AppSettings(); original.microphone=true; original.locale="en-US"; original.microphoneDevice=42
    var testing=original; testing.applicationBundleID="local.audio.intelligence"; testing.microphone=false
    defaults.set(try JSONEncoder().encode(testing),forKey:"settings")
    defaults.set(try JSONEncoder().encode(original),forKey:"audioValidationSettingsBackup")
    let restored=AppSettings.load(from:defaults)
    #expect(restored.applicationBundleID.isEmpty); #expect(restored.microphone); #expect(restored.microphoneDevice==42); #expect(restored.locale=="en-US")
    #expect(defaults.data(forKey:"audioValidationSettingsBackup")==nil)
    #expect(AppSettings.load(from:defaults).microphone)
}

@Test func explicitRebuildReplacesObsoleteFactsWithoutReimportingOldSnapshots() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session); let source=segment(session,0); try await store.append(source)
    let obsolete=Finding(kind:.idea,text:"Interpretación anterior que se desea corregir",segmentID:source.id,quote:source.text,start:0,end:8)
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:1,isFinal:true,findings:[obsolete],processingVersion:2))
    let rebuilt=try #require(try await SummaryCoordinator(store:store).update(session:session,engine:QualityFixtureEngine(),final:true,rebuild:true))
    #expect(rebuilt.isFinal)
    while try await !store.indexNextFindingBatch(session:session.id) {}
    let values=try await store.findings(session:session.id,template:.meeting)
    #expect(!values.contains{$0.text==obsolete.text}); #expect(values.contains{$0.text==source.text})
    #expect(try await store.segments(session:session.id).first?.1.text==source.text)
}

@Test func failedRebuildKeepsThePreviousRegisterUntilAValidBatchCommits() async throws {
    let (directory,store,session)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    try await store.save(session); let source=segment(session,0); try await store.append(source)
    let previous=Finding(kind:.decision,text:source.text,segmentID:source.id,quote:source.text,start:0,end:8)
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:1,isFinal:true,findings:[previous],processingVersion:2))
    await #expect(throws:SummaryResponseError.self) { try await SummaryCoordinator(store:store).update(session:session,engine:IncompleteSummaryEngine(),final:true,rebuild:true) }
    #expect(try await store.findings(session:session.id,template:.meeting).first?.id==previous.id)
    #expect(try await store.latestSummary(session:session.id)?.isFinal==true)
}

@Test(.timeLimit(.minutes(1))) func memoryPressureCancelsRunningAndQueuedRequestsWithoutDroppingFinalJobs() async throws {
    let (directory,store,a)=try fixtureStore(); defer { try? FileManager.default.removeItem(at:directory) }
    let b=Session(title:"Otra sesión",settings:AppSettings())
    try await store.save(a); try await store.save(b)
    try await store.append(segment(a,0)); try await store.append(segment(b,0)); try await store.requestFinalSummary(session:b.id)
    let started=TestLatch(),release=TestLatch(),coordinator=SummaryCoordinator(store:store)
    let engine=CoordinatedEngine(started:started,release:release)
    let running=Task { try await coordinator.update(session:a,engine:engine,final:false) }
    await started.wait()
    let queued=Task { try await coordinator.update(session:b,engine:engine,final:true) }
    while await coordinator.queuedRequests<1 { await Task.yield() }
    await coordinator.cancelAll()
    do { _=try await queued.value; Issue.record("Queued request survived cancellation") } catch is CancellationError {}
    await release.release()
    do { _=try await running.value; Issue.record("Running request survived cancellation") } catch is CancellationError {}
    #expect(try await store.latestSummary(session:a.id)==nil); #expect(try await store.latestSummary(session:b.id)==nil)
    #expect(try await store.pendingFinalSession()?.id==b.id)
}
