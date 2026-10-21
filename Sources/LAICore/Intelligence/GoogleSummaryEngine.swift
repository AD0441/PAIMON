import Foundation

public actor GoogleSummaryEngine:SummarizationEngine {
    private let client:GoogleAIClient
    private let model:String
    private let template:SummaryTemplate
    private let context:SessionContext
    public init(client:GoogleAIClient,model:String,template:SummaryTemplate = .meeting,context:SessionContext = .init()) {
        self.client=client; self.model=model; self.template=template; self.context=context.bounded
    }
    public nonisolated func processingVersion() -> Int { 4 }
    public func identifier() -> String? { context.engineIdentifier(backend:"google",model:model) }
    public func availability(locale:String) async -> String? { await client.availability(model:model) }
    public func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        try Task.checkCancellation()
        if !segments.isEmpty {
            let sources=segments.filter{SummaryGrounding.informative($0.text)}.map(SummarySource.init)
            guard !sources.isEmpty else { return previous }
            let fresh=try await generate(sources:sources,maximumPoints:6)
            var merged=EvidenceValidator.merge(previous:previous,new:fresh)
            let overviews=merged.filter{$0.kind == .overview}.sorted{$0.start<$1.start}
            if overviews.count>8 {
                let group=Array(overviews.prefix(8))
                let compact=try await generate(sources:group.map(SummarySource.init),maximumPoints:0)
                let ids=Set(group.map(\.id))
                merged=EvidenceValidator.merge(previous:merged.filter{!ids.contains($0.id)},new:compact)
            }
            return merged
        }
        guard !previous.isEmpty else { return [] }
        var layer=previous.filter{$0.kind == .overview}
        for kind in [FindingKind.decision,.task,.question,.concept] { layer += previous.filter{$0.kind==kind}.prefix(4) }
        layer.sort{$0.start<$1.start}
        while layer.count>8 {
            var next:[Finding]=[]
            for start in stride(from:0,to:layer.count,by:8) {
                try Task.checkCancellation()
                next += try await generate(sources:Array(layer[start..<min(start+8,layer.count)]).map(SummarySource.init),maximumPoints:0).filter{$0.kind == .overview}
            }
            layer=next
        }
        return try await generate(sources:layer.map(SummarySource.init),maximumPoints:0)
    }
    static func schema(sourceCount:Int,maximumPoints:Int) throws -> Data {
        let text:[String:Any]=["type":"string"]
        let point:[String:Any]=["type":"object","properties":[
            "kind":["type":"string","enum":["idea","decision","task","concept","question","conclusion"]],
            "text":text,"sources":["type":"array","items":["type":"string","enum":(0..<sourceCount).map{"S\($0)"}],"minItems":1,"maxItems":min(3,sourceCount)],
            "owner":text,"due":text],"required":["kind","text","sources","owner","due"]]
        let schema:[String:Any]=["type":"object","properties":["title":text,"overview":text,"points":["type":"array","items":point,"maxItems":maximumPoints]],"required":["title","overview","points"]]
        return try JSONSerialization.data(withJSONObject:schema,options:.sortedKeys)
    }
    private func generate(sources:[SummarySource],maximumPoints:Int) async throws -> [Finding] {
        guard !sources.isEmpty else { throw SummaryResponseError.insufficient }
        let rows=sources.enumerated().map{["id":"S\($0.offset)","text":$0.element.text]}
        let text=try JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys,.withoutEscapingSlashes])
        guard text.count<=32000 else { throw SummaryContextError.exceeded }
        let prompt="""
        Devuelve title (tema breve), overview (síntesis general de 2 a 4 frases, entre 35 y 650 caracteres) y points.
        Cubre todas las fuentes. No conviertas propuestas ni asuntos pendientes en acuerdos. No repitas puntos.
        Añade hasta \(maximumPoints) puntos concretos de máximo 180 caracteres, con sus identificadores S.
        owner y due deben ser cadenas vacías salvo que aparezcan literalmente en las fuentes citadas.
        \(maximumPoints==0 ? "Integra los resúmenes y hechos documentados en una síntesis final coherente; points debe estar vacío.":"")
        FUENTES:\n\(String(decoding:text,as:UTF8.self))
        """
        let data=try await client.generate(model:model,instructions:FoundationSummaryEngine.instructions(for:template)+context.instructions,prompt:prompt,schema:Self.schema(sourceCount:sources.count,maximumPoints:maximumPoints))
        let draft:GroundedSummary
        do { draft=try JSONDecoder().decode(GroundedSummary.self,from:data) }
        catch { throw GoogleAIError.incomplete }
        return try SummaryGrounding.validate(draft,sources:sources,maximumPoints:maximumPoints)
    }
    public func unload() {}
}
