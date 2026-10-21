import Foundation
public actor MLXSummaryEngine: SummarizationEngine {
    private let settings:AppSettings
    private let template:SummaryTemplate
    private let context:SessionContext
    public init(settings:AppSettings,template:SummaryTemplate = .meeting,context:SessionContext = .init()) { self.settings=settings; self.template=template; self.context=context.bounded }
    public func identifier() -> String? { context.engineIdentifier(backend:"mlx",model:settings.mlxModel) }
    public func availability(locale:String) -> String? {
        guard FileManager.default.isExecutableFile(atPath:settings.mlxPython),FileManager.default.fileExists(atPath:settings.mlxScript),FileManager.default.fileExists(atPath:settings.mlxModel+"/config.json") else { return "MLX es opcional. Instala el entorno y selecciona un modelo local Qwen 1.5B/1.7B cuantizado." }; return nil
    }
    public func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        try await InferenceGate.shared.perform { try await self.generate(segments:segments,previous:previous,final:final,locale:locale) }
    }
    private func generate(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        if let reason=availability(locale:locale) { throw LAIError.message(reason) }
        let worker=LocalWorker()
        try await worker.start(executable:settings.mlxPython,arguments:[settings.mlxScript,settings.mlxModel])
        do {
            let data=try JSONSerialization.data(withJSONObject:["instructions":FoundationSummaryEngine.instructions(for:template)+context.instructions,"segments":segments.map{["id":$0.id,"text":$0.text]},"previous":previous.prefix(8).map{["segmentID":$0.segmentID,"text":$0.text,"quote":$0.quote]},"final":final])
            let reply=try await worker.request(data); await worker.stop()
            let draft=try DraftSummary.decodeResponse(reply)
            let findings=EvidenceValidator.validate(draft,segments:segments,previous:previous)
            guard !findings.isEmpty else { throw LAIError.message("MLX devolvió una respuesta sin citas verificables") }
            return EvidenceValidator.merge(previous:previous,new:findings)
        } catch { await worker.stop(); throw error }
    }
    public func unload() {}
}
