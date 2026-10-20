import Foundation
import LAICore

/// Explicit local repair. Build in an isolated store and publish one complete
/// snapshot only after successful generation; never alter source transcription.
func repairSummary(id:UUID,output:URL) async throws {
    let original=try SessionStore()
    guard let session=try await original.session(id:id) else { throw LAIError.message("Sesión no encontrada") }
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("paimon-repair-\(UUID())")
    defer { try? FileManager.default.removeItem(at:directory) }
    let scratch=try SessionStore(directory:directory)
    try await scratch.save(session)
    var cursor:Int64=0; var count=0
    while true {
        let rows=try await original.segments(session:id,after:cursor,limit:100)
        guard !rows.isEmpty else { break }
        for (_,segment) in rows { try await scratch.append(segment); count += 1 }
        cursor=rows.last!.0
    }
    let engine=FoundationSummaryEngine(template:session.template)
    let coordinator=SummaryCoordinator(store:scratch)
    guard var snapshot=try await coordinator.update(session:session,engine:engine,final:true,rebuild:true),snapshot.findings.contains(where:{$0.kind == .overview}) else { throw SummaryResponseError.insufficient }
    try await SessionExporter(store:scratch).export(session:session,to:output,format:.markdown,options:ExportOptions())
    snapshot.throughRow=cursor
    try await original.save(snapshot)
    await engine.unload()
    print("PASS: \(count) fragmentos originales; \(snapshot.findings.count) hallazgos; síntesis general presente; versión \(snapshot.processingVersion ?? 0). Audio y transcripción sin modificar.")
    print("Informe corregido: \(output.path)")
}
