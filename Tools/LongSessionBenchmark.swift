import Foundation
import LAICore

/// Explicit diagnostic only. This engine tests orchestration/storage; it does
/// not pretend to test ASR, model quality, energy or four hours of elapsed audio.
private actor BenchmarkSummaryEngine:SummarizationEngine {
    var calls=0
    nonisolated func processingVersion() -> Int { 2 }
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) -> [Finding] {
        calls += 1
        guard let source=segments.first else { return previous }
        var fresh=segments.map { Finding(kind:.decision,text:$0.text,segmentID:$0.id,quote:$0.text,start:$0.start,end:$0.end) }
        fresh.append(Finding(kind:.overview,text:"Se revisó el presupuesto, la disponibilidad de los equipos y la continuidad de las clases.",segmentID:source.id,quote:source.text,start:source.start,end:source.end))
        // Bound the narrative exactly as a model backend does, while keeping
        // every structured fixture fact available for the ledger stress test.
        let memory=previous.filter{$0.kind != .overview}
        return EvidenceValidator.merge(previous:memory,new:fresh)
    }
    func unload() {}
}

func benchmarkLongSessions(output:URL) async throws {
    var results:[[String:Any]]=[]
    let processBefore=ResourceMetrics.current()
    for minutes in [10,30,60,120,240] {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("paimon-long-\(UUID())")
        let start=ProcessInfo.processInfo.systemUptime,before=ResourceMetrics.current()
        do {
            let store=try SessionStore(directory:directory),engine=BenchmarkSummaryEngine()
            let session=Session(title:"Carga sintética \(minutes) minutos",settings:AppSettings())
            try await store.save(session)
            let coordinator=SummaryCoordinator(store:store)
            var lastUpdate=0.0,peak=before.footprintMB,cursor:Int64=0,queries:[Double]=[],writes:[Double]=[]
            func time(_ began:UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds-began)/1_000_000 }
            for minute in 0..<minutes {
                for part in 0..<6 {
                    let index=minute*6+part
                    let began=DispatchTime.now().uptimeNanoseconds
                    try await store.append(.init(sessionID:session.id,source:.system,start:Double(index*10),end:Double(index*10+9),text:"Etapa \(index): acordamos revisar el presupuesto del laboratorio, comprobar la disponibilidad de los equipos y conservar la continuidad de las clases. Muestra sintética de rendimiento."))
                    writes.append(time(began))
                }
                let elapsed=Double((minute+1)*60),pending=try await store.pendingContent(session:session.id,after:cursor)
                if SummarySchedule.shouldUpdate(pending:pending,secondsSinceUpdate:elapsed-lastUpdate,interval:300,underPressure:false) {
                    if let snapshot=try await coordinator.update(session:session,engine:engine,final:false) { cursor=snapshot.throughRow }
                    lastUpdate=elapsed
                }
                let began=DispatchTime.now().uptimeNanoseconds
                _=try await store.searchTranscripts("presupuesto laboratorio")
                queries.append(time(began))
                peak=max(peak,ResourceMetrics.current().footprintMB)
            }
            let final=try await coordinator.update(session:session,engine:engine,final:true)
            let latest=try await store.latestSummary(session:session.id)
            let pending=try await store.pendingContent(session:session.id,after:latest?.throughRow ?? 0)
            var offset=0,first:Double?,last:Double?
            while true {
                let page=try await store.findings(session:session.id,template:.meeting,limit:120,offset:offset)
                if page.isEmpty { break }
                if first==nil { first=page.first?.start }; last=page.last?.start; offset += page.count
            }
            let visible=try await store.reportFindings(session:session.id,template:.meeting)
            let transcript=try await store.segments(session:session.id,limit:300,newest:true)
            var options=ExportOptions(); options.transcript=false; options.evidence=false
            let url=directory.appendingPathComponent("report.json")
            try await SessionExporter(store:store).export(session:session,to:url,format:.json,options:options)
            // Verify the exported register without retaining the document after this scenario.
            let json=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]
            let exported=(json?["findings"] as? [[String:Any]])?.filter{$0["kind"] as? String=="decision"}.count ?? 0
            let passed=(final?.isFinal ?? latest?.isFinal)==true && pending.segments==0 && offset==minutes*6 && exported==offset && first==0 && last==Double((minutes*6-1)*10) && visible.count<=136 && transcript.count<=300
            func stats(_ values:[Double]) -> [String:Double] { let sorted=values.sorted(); return ["p50ms":sorted[sorted.count/2],"p95ms":sorted[Int(Double(sorted.count-1)*0.95)],"maxMs":sorted.last ?? 0] }
            let after=ResourceMetrics.current()
            results.append(["scenarioMinutes":minutes,"fixtureSegments":minutes*6,"durableDecisions":offset,"exportedDecisions":exported,"visibleFindings":visible.count,"visibleTranscriptSegments":transcript.count,"pendingSegments":pending.segments,"inferenceFixtureCalls":await engine.calls,"wallSeconds":ProcessInfo.processInfo.systemUptime-start,"cpuSeconds":after.cpuSeconds-before.cpuSeconds,"clientFootprintStartMB":before.footprintMB,"clientFootprintEndMB":after.footprintMB,"sampledClientPeakMB":max(peak,after.footprintMB),"queries":stats(queries),"writes":stats(writes),"passed":passed])
            guard passed else { throw LAIError.message("Falló el escenario de \(minutes) minutos") }
        } catch { try? FileManager.default.removeItem(at:directory); throw error }
        try FileManager.default.removeItem(at:directory)
    }
    let report:[String:Any]=["synthetic":true,"accelerated":true,"nativeModelsLoaded":false,"audioCaptured":false,"note":"Accelerated transcript orchestration and SQLite stress test; not a real 240-minute audio soak, ASR/LLM benchmark or energy measurement.","scenarios":results,"clientFootprintBeforeMB":processBefore.footprintMB,"clientFootprintAfterMB":ResourceMetrics.current().footprintMB]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
    print("PASS: accelerated 10/30/60/120/240-minute fixtures; complete cursors and durable/exported decisions.")
}
