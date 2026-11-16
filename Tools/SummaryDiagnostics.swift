import Foundation
import LAICore

/// Explicit local diagnostic. Never exports source text, generated text or session names.
/// The original transcript and summary are not modified.
func diagnoseSummaryBlock(id:UUID,output:URL) async throws {
    let store=try SessionStore()
    guard let session=try await store.session(id:id) else { throw LAIError.message("Sesión no encontrada") }
    let rows=try await store.segments(session:id,limit:30)
    var batch:[TranscriptSegment]=[],bytes=0
    for (_,segment) in rows {
        if segment.duplicateOf != nil { continue }
        let count=segment.text.utf8.count
        if !batch.isEmpty && bytes+count>2800 { break }
        batch.append(segment); bytes += count
    }
    let engine=FoundationSummaryEngine(template:session.template,context:session.context ?? .init())
    let start=ProcessInfo.processInfo.systemUptime
    var record:[String:Any]=["privateSource":true,"sourceTextExported":false,"sourceCount":batch.count,"inputBytes":bytes,"summarySaved":false]
    do {
        let values=try await engine.summarize(segments:batch,previous:[],final:false,locale:session.settings.locale)
        record["outcome"]="completed"
        record["findings"]=values.count
        record["overviewPresent"]=values.contains{$0.kind == .overview}
    } catch {
        record["outcome"]="failed"
        record["errorType"]=String(reflecting:type(of:error))
        if let failure=error as? SummaryResponseError {
            switch failure {
            case .rejected(let reason,let count): record["rejectionReason"]=reason.rawValue; record["overviewCharacters"]=count
            case .insufficient: record["rejectionReason"]="insufficient"
            case .incomplete: record["rejectionReason"]="incomplete"
            case .ungrounded: record["rejectionReason"]="ungrounded"
            }
        }
    }
    await engine.unload()
    record["elapsedSeconds"]=ProcessInfo.processInfo.systemUptime-start
    record["clientFootprintMB"]=ResourceMetrics.current().footprintMB
    try JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
    print("Diagnóstico local guardado sin texto ni audio.")
}
