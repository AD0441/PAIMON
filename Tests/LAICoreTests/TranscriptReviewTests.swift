import Foundation
import Testing
@testable import LAICore

private func reviewSegment(_ session: Session, text: String = "hola paimon, la reunion comienza.") -> TranscriptSegment {
    .init(sessionID: session.id, source: .file, start: 12, end: 20, text: text)
}
private func change(_ segment: TranscriptSegment, _ original: String, _ replacement: String,
                    kind: TranscriptReviewKind = .spelling) -> TranscriptReviewChange {
    .init(segmentID: segment.id, original: original, replacement: replacement, kind: kind, reason: "Corrección formal.", needsAudio: false)
}

@Test func intelligentReviewRejectsInventedAmbiguousAndProtectedChanges() {
    let session=Session(title:"Revisión sintética",settings:AppSettings())
    let segment=reviewSegment(session,text:"No pagó 25 pesos. sí, sí. La reunion.")
    let valid=change(segment,"reunion","reunión")
    let changes=[valid,change(segment,"25","50"),change(segment,"No","Sí"),
                 change(segment,"sí","si"),change(segment,"ausente","inventado")]
    let values=TranscriptReviewer.verified(changes,segment:segment,batch:"test",mode:.complete)
    #expect(values.count==1)
    #expect(values.first?.replacement=="reunión")
    #expect(values.first?.lowRisk==false)
    #expect(TranscriptReviewer.pieces(String(repeating:"una palabra ",count:400)).joined()==String(repeating:"una palabra ",count:400))
}

@Test func intelligentReviewRequiresManualVerificationForNamesAndRejectsOverlap() {
    let session=Session(title:"Revisión sintética",settings:AppSettings())
    let segment=reviewSegment(session)
    let values=TranscriptReviewer.verified([change(segment,"paimon","PAIMON",kind:.name),
        change(segment,"hola paimon","Hola PAIMON"),change(segment,"reunion","reunión")],
        segment:segment,batch:"test",mode:.complete)
    #expect(values.count==2)
    #expect(values.first?.needsAudio==true)
    #expect(values.first?.lowRisk==false)
    #expect(TranscriptReviewer.verified([change(segment,"paimon","PAIMON",kind:.name)],
        segment:segment,batch:"test",mode:.formal).isEmpty)
}

@Test func intelligentReviewAcceptsMultipleEditsWithoutLosingOriginalAndPurgesWithSession() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Revisión sintética",settings:AppSettings()); session.status="completed"
    try await store.save(session)
    let segment=reviewSegment(session)
    try await store.append(segment)
    let values=TranscriptReviewer.verified([change(segment,"hola","Hola"),change(segment,"reunion","reunión")],
        segment:segment,batch:"test",mode:.formal)
    let revision=try await store.transcriptRevision(session:session.id)
    try await store.saveReviewBatch(values,session:session.id,batch:"test",segment:segment,expectedRevision:revision)
    let first=try await store.acceptReview(id:values[0].id,session:session.id)
    #expect(first.originalText==segment.text)
    let second=try await store.acceptReview(id:values[1].id,session:session.id)
    #expect(second.text=="Hola paimon, la reunión comienza.")
    #expect(second.originalText==segment.text)
    #expect(second.start==segment.start && second.end==segment.end && second.id==segment.id)
    #expect(try await store.reviewSuggestions(session:session.id).allSatisfy{$0.state == .accepted})
    #expect(try await store.reviewWasCompleted(session:session.id,batch:"test"))
    try await store.delete(session:session.id)
    #expect(try await store.reviewSuggestions(session:session.id).isEmpty)
    #expect(try await !store.reviewWasCompleted(session:session.id,batch:"test"))
}

@Test func intelligentReviewDeclinesStaleEditsAndRetainsRejectedState() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Revisión sintética",settings:AppSettings()); session.status="completed"
    try await store.save(session)
    let segment=reviewSegment(session)
    try await store.append(segment)
    let values=TranscriptReviewer.verified([change(segment,"hola","Hola"),change(segment,"reunion","reunión")],
        segment:segment,batch:"stale",mode:.formal)
    try await store.saveReviewBatch(values,session:session.id,batch:"stale",segment:segment,expectedRevision:0)
    try await store.rejectReview(id:values[0].id,session:session.id)
    _=try await store.correctSegment(session:session.id,id:segment.id,text:"Texto cambiado manualmente.")
    await #expect(throws:(any Error).self) { try await store.acceptReview(id:values[1].id,session:session.id) }
    #expect(try await store.reviewSuggestions(session:session.id).first(where:{$0.id==values[0].id})?.state == .rejected)
}

@Test func intelligentReviewDoesNotBulkAcceptAccentsOrChangedNumericFormats() {
    let session=Session(title:"Revisión sintética",settings:AppSettings())
    let segment=reviewSegment(session,text:"si pago -1,5% mañana")
    let edits=[change(segment,"si","sí"),change(segment,"-1,5%","1,5%"),change(segment,"-1,5%","-1.5%")]
    let verified=TranscriptReviewer.verified(edits,segment:segment,batch:"numeric",mode:.formal)
    #expect(verified.count==1)
    #expect(verified.first?.original=="si")
    #expect(verified.first?.lowRisk==false)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_APPLE_REVIEW"] == "1"), .timeLimit(.minutes(2)))
func intelligentReviewCallsTheNativeModelAndCheckpointsItsValidatedResults() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Revisión sintética",settings:AppSettings()); session.status="completed"
    session.context=SessionContext(objective:"Revisar un acta",glossary:"PAIMON")
    try await store.save(session)
    let segment=reviewSegment(session,text:"hola, la reunion comienza mañana.")
    try await store.append(segment)
    try await TranscriptReviewer.review(session:session,store:store,mode:.formal) { _ in }
    let suggestions=try await store.reviewSuggestions(session:session.id)
    #expect(suggestions.allSatisfy { $0.state == .pending && $0.sourceText==segment.text })
    let original=try await store.segments(session:session.id)
    #expect(original.first?.1.text==segment.text)
}

@Test func intelligentReviewExportCanSelectOriginalWhileKeepingCurrentEdits() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Exportación sintética",settings:AppSettings()); session.status="completed"
    try await store.save(session)
    let segment=reviewSegment(session)
    try await store.append(segment)
    _=try await store.correctSegment(session:session.id,id:segment.id,text:"Hola PAIMON, la reunión comienza.")
    var options=ExportOptions(); options.originalTranscript=true; options.kinds=[]
    let url=directory.appendingPathComponent("original.json")
    try await SessionExporter(store:store).export(session:session,to:url,format:.json,options:options)
    let object=try #require(try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
    let transcript=try #require(object["transcript"] as? [[String:Any]])
    #expect(transcript.first?["text"] as? String == segment.text)
    #expect(try await store.segments(session:session.id).first?.1.text == "Hola PAIMON, la reunión comienza.")
}
