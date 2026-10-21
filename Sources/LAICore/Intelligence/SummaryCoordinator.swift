import Foundation
import os

public actor SummaryCoordinator {
    private let store:SessionStore
    private struct Request {
        var id=UUID()
        var session:Session
        var engine:any SummarizationEngine
        var final:Bool
        var rebuild:Bool
        var waiters:[UUID:CheckedContinuation<SummarySnapshot?,any Error>]
    }
    private var running:Request?
    private var pending:[Request]=[]
    private var task:Task<Void,Never>?
    public var queuedRequests:Int { pending.reduce(0){$0+$1.waiters.count} }
    private let signposter=OSSignposter(subsystem:"local.audio.intelligence",category:"Summary")
    public init(store:SessionStore) { self.store=store }

    /// Coalesce pending updates per session. A Stop request always gets a turn,
    /// taking its watermark after the ASR tail has been persisted.
    public func update(session:Session,engine:any SummarizationEngine,final:Bool,rebuild:Bool=false) async throws -> SummarySnapshot? {
        let id=UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if let index=pending.firstIndex(where:{$0.session.id==session.id && $0.session.template==session.template}) {
                    guard pending[index].waiters.count<32 else { continuation.resume(throwing:LAIError.message("Hay demasiadas solicitudes de resumen pendientes")); return }
                    pending[index].final = pending[index].final || final
                    pending[index].rebuild = pending[index].rebuild || rebuild
                    pending[index].session=session; pending[index].engine=engine
                    pending[index].waiters[id]=continuation
                } else {
                    guard pending.count<8 else { continuation.resume(throwing:LAIError.message("La cola de resúmenes está ocupada")); return }
                    pending.append(Request(session:session,engine:engine,final:final,rebuild:rebuild,waiters:[id:continuation]))
                }
                startNext()
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    public func cancel(session:UUID) {
        for request in pending.filter({$0.session.id==session}) { for waiter in request.waiters.values { waiter.resume(throwing:CancellationError()) } }
        pending.removeAll{$0.session.id==session}
        if running?.session.id==session { task?.cancel() }
    }
    public func cancelAll() {
        for request in pending { for waiter in request.waiters.values { waiter.resume(throwing:CancellationError()) } }
        pending=[]; task?.cancel()
    }
    private func cancel(_ waiterID:UUID) {
        if let waiter=running?.waiters.removeValue(forKey:waiterID) {
            waiter.resume(throwing:CancellationError())
            if running?.waiters.isEmpty==true { task?.cancel() }
        }
        for index in pending.indices.reversed() {
            if let waiter=pending[index].waiters.removeValue(forKey:waiterID) { waiter.resume(throwing:CancellationError()) }
            if pending[index].waiters.isEmpty { pending.remove(at:index) }
        }
    }
    private func startNext() {
        guard running==nil,!pending.isEmpty else { return }
        let request=pending.removeFirst(); running=request
        task=Task {
            let result:Result<SummarySnapshot?,any Error>
            do { result = .success(try await process(request)) } catch { result = .failure(error) }
            complete(request.id,result:result)
        }
    }
    private func complete(_ id:UUID,result:Result<SummarySnapshot?,any Error>) {
        guard running?.id==id else { return }
        let waiters=running?.waiters.values
        running=nil; task=nil
        if let waiters { for waiter in waiters { waiter.resume(with:result) } }
        startNext()
    }

    private func process(_ request:Request) async throws -> SummarySnapshot? {
        let session=request.session,engine=request.engine,final=request.final
        let start=ProcessInfo.processInfo.systemUptime,before=ResourceMetrics.current()
        let interval=signposter.beginInterval("Summary update")
        var batches=0,reductions=0,pendingCount=0,cursor:Int64=0
        do {
            try Task.checkCancellation()
            var previous=try await store.latestSummary(session:session.id)
            let version=await engine.processingVersion()
            let identity=await engine.identifier()
            var replaceRegister=request.rebuild || (previous?.summaryTemplate ?? .meeting) != session.template || (previous != nil && (previous?.processingVersion ?? 0)<version)
            if let identity,let previous,previous.engineIdentifier != identity { replaceRegister=true }
            if replaceRegister { previous=nil }
            cursor=previous?.throughRow ?? 0
            pendingCount=try await store.pendingContent(session:session.id,after:cursor).segments
            let watermark=try await store.segments(session:session.id,limit:1,newest:true).last?.0 ?? 0
            if cursor>=watermark && (!final || previous?.isFinal==true) {
                signposter.endInterval("Summary update",interval)
                return nil
            }
            var didWork=false
            while cursor<watermark {
                try Task.checkCancellation()
                let rows=try await store.segments(session:session.id,after:cursor,limit:30,before:watermark+1)
                if rows.isEmpty { break }
                var batch:[TranscriptSegment]=[],bytes=0,end=cursor
                for (seq,segment) in rows {
                    if segment.duplicateOf != nil { end=seq; continue }
                    let count=segment.text.utf8.count
                    if !batch.isEmpty && bytes+count>2800 { break }
                    batch.append(segment); bytes += count; end=seq
                }
                let result=try await summarize(batch,previous:previous?.findings ?? [],engine:engine,session:session,version:version,depth:0)
                reductions += result.reductions; batches += result.calls
                let findings=result.memory
                if version>=2,batch.contains(where:{SummaryGrounding.informative($0.text)}),!findings.contains(where:{$0.kind == .overview}) { throw SummaryResponseError.insufficient }
                try Task.checkCancellation()
                var snapshot=SummarySnapshot(sessionID:session.id,throughRow:end,isFinal:false,findings:findings,template:session.template,processingVersion:version)
                snapshot.engineIdentifier=identity
                try await store.save(snapshot,additionalFindings:result.facts,replaceRegister:replaceRegister)
                replaceRegister=false
                previous=snapshot; cursor=end; didWork=true
            }
            if final,let prior=previous {
                while try await !store.indexNextFindingBatch(session:session.id) { try Task.checkCancellation(); await Task.yield() }
            let facts=try await store.finalContext(session:session.id,template:session.template)
                let context=EvidenceValidator.merge(previous:prior.findings,new:facts)
                let integrated=try await engine.summarize(segments:[],previous:context,final:true,locale:session.settings.locale)
                batches += 1
                if version>=2,!integrated.contains(where:{$0.kind == .overview}) { throw SummaryResponseError.insufficient }
                try Task.checkCancellation()
                let retained=EvidenceValidator.merge(previous:prior.findings.filter{$0.kind != .overview && $0.kind != .topic},new:integrated)
                var snapshot=SummarySnapshot(sessionID:session.id,throughRow:cursor,isFinal:true,findings:retained,template:session.template,processingVersion:version)
                snapshot.engineIdentifier=identity
                try await store.save(snapshot); previous=snapshot; didWork=true
            }
            await record(session:session.id,start:start,before:before,pending:pendingCount,batches:batches,reductions:reductions,cursor:cursor,final:final,outcome:"completed")
            signposter.endInterval("Summary update",interval)
            return didWork ? previous:nil
        } catch {
            await record(session:session.id,start:start,before:before,pending:pendingCount,batches:batches,reductions:reductions,cursor:cursor,final:final,outcome:error is CancellationError ? "cancelled":error is SummaryContextError ? "context":"failed")
            signposter.endInterval("Summary update",interval)
            throw error
        }
    }
    private struct BatchResult { var memory:[Finding]; var facts:[Finding]; var reductions=0; var calls=0 }
    private func summarize(_ segments:[TranscriptSegment],previous:[Finding],engine:any SummarizationEngine,session:Session,version:Int,depth:Int) async throws -> BatchResult {
        try Task.checkCancellation()
        guard !segments.isEmpty else { return BatchResult(memory:previous,facts:[]) }
        do {
            let output=try await engine.summarize(segments:segments,previous:previous,final:false,locale:session.settings.locale)
            return BatchResult(memory:EvidenceValidator.merge(previous:previous.filter{$0.kind != .overview && $0.kind != .topic},new:output),facts:output.filter{$0.kind != .overview && $0.kind != .topic},calls:1)
        } catch {
            try Task.checkCancellation()
            if error is SummaryContextError,depth<8 {
                let pieces:[[TranscriptSegment]]
                if segments.count>1 {
                    let mid=segments.count/2; pieces=[Array(segments[..<mid]),Array(segments[mid...])]
                } else if let original=segments.first,original.text.utf8.count>400 {
                    let mid=original.text.index(original.text.startIndex,offsetBy:original.text.count/2)
                    let boundary=original.text[mid...].firstIndex(where:{$0.isWhitespace}) ?? mid
                    var a=original,b=original
                    a.text=String(original.text[..<boundary]); b.text=String(original.text[boundary...])
                    guard !a.text.isEmpty,!b.text.isEmpty else { throw error }; pieces=[[a],[b]]
                } else { throw error }
                var result=BatchResult(memory:previous,facts:[],reductions:1)
                for piece in pieces {
                    let next=try await summarize(piece,previous:result.memory,engine:engine,session:session,version:version,depth:depth+1)
                    result.memory=next.memory; result.facts += next.facts; result.reductions += next.reductions; result.calls += next.calls
                }
                return result
            }
            guard version<2,!(error is CancellationError) else { throw error }
            let fresh=try await engine.summarize(segments:segments,previous:[],final:false,locale:session.settings.locale)
            return BatchResult(memory:EvidenceValidator.merge(previous:previous,new:fresh),facts:fresh.filter{$0.kind != .overview && $0.kind != .topic},calls:2)
        }
    }
    private func record(session:UUID,start:Double,before:ResourceMetrics,pending:Int,batches:Int,reductions:Int,cursor:Int64,final:Bool,outcome:String) async {
        let after=ResourceMetrics.current()
        try? await store.save(SummaryRunMetrics(sessionID:session,seconds:ProcessInfo.processInfo.systemUptime-start,cpuSeconds:max(0,after.cpuSeconds-before.cpuSeconds),clientFootprintMB:after.footprintMB,pendingSegments:pending,processedBatches:batches,contextReductions:reductions,throughRow:cursor,final:final,outcome:outcome))
    }
}
