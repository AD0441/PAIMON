import Foundation
public actor MLXSummaryEngine: SummarizationEngine {
    private let settings:AppSettings
    private let template:SummaryTemplate
    private let context:SessionContext
    public init(settings:AppSettings,template:SummaryTemplate = .meeting,context:SessionContext = .init()) { self.settings=settings; self.template=template; self.context=context.bounded }
    private var modelPath:String {
        settings.mlxModel.isEmpty ? OptionalModelPackage.mlx.directory.path:settings.mlxModel
    }
    public func identifier() -> String? { context.engineIdentifier(backend:"mlx",model:modelPath) }

    private var runtime:(python:String,script:String)? {
        let path=URL(fileURLWithPath:modelPath,isDirectory:true)
        let managed=path.path==OptionalModelPackage.mlx.directory.path
        let python=managed ? ManagedMLXRuntime.python(in:path).path:settings.mlxPython
        let script=managed ? ManagedMLXRuntime.workerScript?.path ?? "":settings.mlxScript
        guard FileManager.default.isExecutableFile(atPath:python),
              FileManager.default.fileExists(atPath:script),
              FileManager.default.fileExists(atPath:path.appendingPathComponent("config.json").path),
              !managed || ManagedMLXRuntime.isReady(in:path) else { return nil }
        return (python,script)
    }
    public func availability(locale:String) -> String? {
        runtime == nil ? "Descarga el modelo y el entorno MLX en Ajustes → Modelos.":nil
    }
    public func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        try await InferenceGate.shared.perform { try await self.generate(segments:segments,previous:previous,final:final,locale:locale) }
    }
    private func generate(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        guard let runtime else { throw LAIError.message("Descarga el modelo y el entorno MLX en Ajustes → Modelos.") }
        let worker=LocalWorker()
        try await worker.start(executable:runtime.python,arguments:["-I",runtime.script,modelPath])
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
