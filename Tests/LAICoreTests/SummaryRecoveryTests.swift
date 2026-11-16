import Foundation
import Testing
import FoundationModels
@testable import LAICore

@Test(arguments:[0,34,651,900])
func overviewRejectionReportsItsLengthWithoutExposingSourceText(_ count:Int) throws {
    let text=String(repeating:"biblioteca catálogo digital ",count:40)
    let source=SummarySource(TranscriptSegment(sessionID:UUID(),source:.file,start:0,end:10,text:text))
    let json=try JSONSerialization.data(withJSONObject:["title":"Catálogo","overview":String(text.prefix(count))])
    let draft=try JSONDecoder().decode(GroundedSummary.self,from:json)
    do {
        _=try SummaryGrounding.validate(draft,sources:[source],maximumPoints:0)
        Issue.record("Invalid overview length was accepted")
    } catch let error as SummaryResponseError {
        guard case .rejected(.overviewLength,let actual)=error else { Issue.record("Wrong rejection reason"); return }
        #expect(actual==count)
        #expect(error.localizedDescription.contains(text)==false)
        #expect(SummaryResponseError.isRetryable(error))
    }
}

@Test(arguments:[35,650])
func validOverviewLengthBoundariesKeepOriginalEvidence(_ count:Int) throws {
    let text=String(repeating:"La biblioteca prepara un catálogo digital para consultar libros. ",count:15)
    let segment=TranscriptSegment(sessionID:UUID(),source:.file,start:0,end:10,text:text)
    let json=try JSONSerialization.data(withJSONObject:["title":"Catálogo","overview":String(text.prefix(count-1))+"."])
    let result=try SummaryGrounding.validate(JSONDecoder().decode(GroundedSummary.self,from:json),sources:[SummarySource(segment)],maximumPoints:0)
    #expect(result.first{$0.kind == .overview}?.text.count==count)
    #expect(result.first{$0.kind == .overview}?.quote==text)
}

@Test(.enabled(if:ProcessInfo.processInfo.environment["PAIMON_TEST_SUMMARY"]=="1"),.timeLimit(.minutes(3)))
func nativeSummaryOfManySourcesProducesABoundedOverviewAndVerifiablePoints() async throws {
    let paragraphs=[
        "La biblioteca propone incorporar un catálogo digital para consultar la ubicación y disponibilidad de los libros del campus.",
        "El laboratorio necesita revisar el estado de los microscopios y comparar alternativas de reparación y compra antes de renovar los equipos.",
        "Para las salas se propone un calendario de reservas que muestre los horarios disponibles y permita evitar reservas duplicadas.",
        "Los talleres explicarán al personal cómo consultar el catálogo de biblioteca y actualizar los registros de libros. Falta definir el calendario de formación."
    ]
    let id=UUID()
    let segments=(0..<16).map { i in TranscriptSegment(sessionID:id,source:.file,start:Double(i*10),end:Double(i*10+8),text:paragraphs[i%4]) }
    let engine=FoundationSummaryEngine()
    let findings=try await engine.summarize(segments:segments,previous:[],final:false,locale:"es-ES")
    let overview=try #require(findings.first{$0.kind == .overview})
    #expect((35...650).contains(overview.text.count))
    #expect(findings.contains{$0.kind == .idea || $0.kind == .concept})
    for finding in findings {
        #expect(finding.evidence.allSatisfy{ evidence in segments.contains{$0.id==evidence.segmentID && $0.text==evidence.quote} })
        #expect(finding.owner==nil && finding.due==nil)
    }
    await engine.unload()
}

@Test func legacySummaryErrorsRemainRecoverableOnNewerSystems() {
    let context=LanguageModelSession.GenerationError.Context(debugDescription:"Synthetic diagnostic")
    #expect(SummaryResponseError.isRetryable(LanguageModelSession.GenerationError.decodingFailure(context)))
    #expect(FoundationSummaryEngine.contextExceeded(LanguageModelSession.GenerationError.exceededContextWindowSize(context)))
    #expect(FoundationSummaryEngine.contextExceeded(SummaryContextError.exceeded))
}
