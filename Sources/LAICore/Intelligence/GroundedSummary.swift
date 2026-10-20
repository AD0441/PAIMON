import Foundation
import FoundationModels

/// Compact model inputs carry local aliases. Quotes and clocks always come from
/// the persisted source, never from generated JSON.
struct SummarySource:Sendable {
    var text:String
    var evidence:[FindingEvidence]
    init(_ segment:TranscriptSegment) {
        text=segment.text
        evidence=[.init(segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end)]
    }
    init(_ finding:Finding) { text=finding.text; evidence=finding.evidence }
}
struct GroundedPoint:Decodable,Sendable {
    var kind:String
    var text:String
    var sources:[String]
    var owner:String?
    var due:String?
}
struct GroundedSummary:Decodable,Sendable {
    var title:String
    var overview:String
    var points:[GroundedPoint]
    enum CodingKeys:String,CodingKey { case title,overview,points }
    init(from decoder:any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        title=try c.decode(String.self,forKey:.title)
        overview=try c.decode(String.self,forKey:.overview)
        points=try c.decodeIfPresent([GroundedPoint].self,forKey:.points) ?? []
    }
    static func schema(sourceCount:Int,maximumPoints:Int) throws -> GenerationSchema {
        let text=DynamicGenerationSchema(type:String.self)
        var properties:[DynamicGenerationSchema.Property]=[
            .init(name:"title",description:"Tema concreto en menos de 8 palabras",schema:text),
            .init(name:"overview",description:"Resumen general obligatorio: 2 a 4 frases breves que cubran los temas del material; máximo 650 caracteres",schema:text)
        ]
        if maximumPoints>0 {
            let point=DynamicGenerationSchema(name:"SupportedPoint",properties:[
                .init(name:"kind",description:"Propuestas y planes son idea; decision exige acuerdo explícito sobre ese punto, task un encargo concreto. Algo que falta decidir es question, nunca decision",schema:.init(name:"PointKind",anyOf:["idea","decision","task","concept","question","conclusion"])),
                .init(name:"text",description:"Un punto relevante, concreto, fiel a las fuentes, máximo 180 caracteres",schema:text),
                .init(name:"sources",description:"Identificadores de las fuentes que respaldan este punto",schema:.init(arrayOf:.init(name:"Source",anyOf:(0..<sourceCount).map{"S\($0)"}),minimumElements:1,maximumElements:min(3,sourceCount))),
                .init(name:"owner",description:"Responsable copiado literalmente de las fuentes; cadena vacía si no existe",schema:text),
                .init(name:"due",description:"Fecha copiada literalmente de las fuentes; cadena vacía si no existe",schema:text)
            ])
            properties.append(.init(name:"points",description:"Hechos y propuestas importantes de distintas partes del material. Omite saludos y problemas de conexión resueltos",schema:.init(arrayOf:point,minimumElements:0,maximumElements:maximumPoints)))
        }
        return try GenerationSchema(root:.init(name:"GroundedSummary",properties:properties),dependencies:[])
    }
}

enum SummaryGrounding {
    // A conservative lexical relevance check, not a semantic proof. It catches
    // unrelated citations such as an introductory fragment backing a broad claim.
    private static let stop:Set<String>=Set("a al algo ante aqui asi aun bien cada como con contra cual cuando de del desde donde dos durante e el ella ellas ellos en entre era es esa esas ese eso esos esta estaba estamos estan estar estas este esto estos fue ha hacia han hasta hay hoy incluso la las le les lo los mas me mi mis mucha muchas mucho muchos muy ni no nos nuestra nuestras nuestro nuestros o otra otras otro otros para parte pero por porque pues que quien quienes se sea ser si sido sin sobre somos son su sus tambien tanto te tener tiene tienen todo todos tras tu un una unas uno unos ustedes va vamos vez ya y yo area senor senora nombre noches buenas buenos dia dias gracias entonces sentido caso ello ello tenemos teniamos mencionar escuchar presentacion presentar empezar continuar".split(separator:" ").map(String.init))
    static func words(_ text:String) -> Set<String> {
        Set(text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"es"))
            .components(separatedBy:CharacterSet.alphanumerics.inverted)
            .filter{$0.count>=3 && !stop.contains($0)}.map{String($0.prefix(6))})
    }
    static func informative(_ text:String) -> Bool { words(text).count>=3 || explicitDecision(text) }
    static func supports(_ text:String,source:String) -> Bool {
        let claim=words(text),content=words(source)
        guard !claim.isEmpty else { return false }
        let matches=claim.intersection(content).count
        return matches>=min(2,claim.count) && Double(matches)/Double(claim.count)>=0.2
    }
    static func explicitDecision(_ text:String) -> Bool {
        let literal=text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:nil)
        return ["acordamos","se acordo","decidimos","se decidio","aprobamos","se aprobo","resolvimos","se resolvio","we agreed","we decided","it was decided","approved"].contains(where:literal.contains)
    }
    static func supportsDecision(_ claim:String,quote:String) -> Bool {
        // One segment may contain both an agreement and an unresolved matter.
        // An agreement cue in another sentence cannot authorize this claim.
        quote.components(separatedBy:CharacterSet(charactersIn:".!?;\n"))
            .contains { explicitDecision($0) && supports(claim,source:$0) }
    }
    static func references(_ sources:[SummarySource],claim:String?=nil) -> [FindingEvidence] {
        var seen=Set<FindingEvidence>()
        let keywords=claim.map(words)
        let all=sources.flatMap(\.evidence).filter {
            guard seen.insert($0).inserted else { return false }
            if let keywords { return keywords.intersection(words($0.quote)).count>=min(2,keywords.count) }
            return true
        }.sorted{$0.start<$1.start}
        guard all.count>12 else { return all }
        // Keep references spread across the full span, including both ends.
        return (0..<12).map { all[$0*(all.count-1)/11] }
    }
    static func finding(kind:FindingKind,text:String,sources:[SummarySource],owner:String?=nil,due:String?=nil) -> Finding? {
        let text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        let material=sources.map(\.text).joined(separator:"\n")
        let evidence=references(sources,claim:text)
        guard !text.isEmpty,text.count<=1200,supports(text,source:material),let first=evidence.first else { return nil }
        let quotes=evidence.map(\.quote).joined(separator:"\n")
        if kind == .decision && !supportsDecision(text,quote:quotes) { return nil }
        func literal(_ value:String?) -> String? { guard let value,!value.isEmpty,quotes.contains(value) else { return nil }; return value }
        return .init(kind:kind,text:text,segmentID:first.segmentID,quote:first.quote,start:first.start,end:first.end,owner:literal(owner),due:literal(due),additionalEvidence:Array(evidence.dropFirst()))
    }
    static func validate(_ draft:GroundedSummary,sources:[SummarySource],maximumPoints:Int) throws -> [Finding] {
        guard (35...650).contains(draft.overview.count),let overview=finding(kind:.overview,text:draft.overview,sources:sources) else { throw SummaryResponseError.insufficient }
        var result:[Finding]=[]
        if let topic=finding(kind:.topic,text:draft.title,sources:sources) { result.append(topic) }
        result.append(overview)
        for point in draft.points.prefix(maximumPoints) {
            guard point.text.count<=220 else { continue }
            let refs=point.sources.compactMap { alias -> SummarySource? in
                guard alias.hasPrefix("S"),let index=Int(alias.dropFirst()),sources.indices.contains(index) else { return nil }; return sources[index]
            }
            guard refs.count==point.sources.count,let kind=FindingKind(rawValue:point.kind),kind != .overview,kind != .topic else { continue }
            if let value=finding(kind:kind,text:point.text,sources:refs,owner:point.owner,due:point.due) { result.append(value) }
        }
        if maximumPoints>0,sources.map(\.text).joined().count>500,!result.contains(where:{$0.kind != .topic && $0.kind != .overview}) { throw SummaryResponseError.insufficient }
        return result
    }
}
