import Foundation
import Testing
@testable import LAICore

@Test func assistantSearchIsBoundedAndScopedToTheSelectedSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    let session = Session(title: "Reunión de prueba", settings: AppSettings())
    let other = Session(title: "Otra sesión", settings: AppSettings())
    try await store.save(session)
    try await store.save(other)

    for index in 0..<24 {
        let start = Double(index * 10)
        let text = index == 18 ? "Se acordó comprar dos micrófonos." : "Fragmento de prueba \(index)."
        try await store.append(.init(sessionID: session.id, source: .file, start: start, end: start + 5, text: text))
    }
    var duplicate = TranscriptSegment(sessionID: session.id, source: .microphone, start: 180, end: 185, text: "Se acordó comprar dos micrófonos.")
    duplicate.duplicateOf = "file-180000"
    try await store.append(duplicate)
    try await store.append(.init(sessionID: other.id, source: .file, start: 0, end: 5, text: "Micrófonos de otra reunión."))

    let context = try await store.assistantContext(session: session, keywords: TranscriptAssistant.keywords(for: "¿Qué micrófonos?"), anchors: ["file-170000"])
    #expect(context.count == 25)
    #expect(context.segments.count <= 12)
    #expect(context.segments.allSatisfy { $0.sessionID == session.id && $0.duplicateOf == nil })
    #expect(context.segments.first?.id == "file-180000")
    #expect(context.segments.contains { $0.id == "file-170000" })
    #expect(Set(context.segments.map(\.id)).count == context.segments.count)
}

@Test func assistantRequiresOriginalQuotesAndReturnsTheirSource() {
    let segment = TranscriptSegment(sessionID: UUID(), source: .file, start: 12, end: 20,
                                    text: "Se acordó comprar dos micrófonos.")
    let sources = [TranscriptAssistant.Source(key: "F1", segment: segment, text: segment.text)]
    let answer = "Se acordó comprar dos micrófonos."
    let fabricated = TranscriptAssistantDraft(answer: answer, citations: [.init(source: "F1", quote: "Se acordó comprar cámaras.")])
    let wrongID = TranscriptAssistantDraft(answer: answer, citations: [.init(source: "F2", quote: answer)])
    let valid = TranscriptAssistantDraft(answer: answer, citations: [.init(source: "F1", quote: answer)])
    #expect(TranscriptAssistant.verified(fabricated, sources: sources, sampled: true).text == nil)
    #expect(TranscriptAssistant.verified(wrongID, sources: sources, sampled: true).text == nil)
    let reply = TranscriptAssistant.verified(valid, sources: sources, sampled: false)
    #expect(reply.text == answer)
    #expect(reply.evidence == [.init(segmentID: segment.id, quote: answer, start: 12, end: 20)])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_ASSISTANT_FOUNDATION"] == "1"), .timeLimit(.minutes(1)))
func assistantAnswersAndAbstainsWithTheLocalAppleModel() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    let session = Session(title: "Prueba del asistente", settings: AppSettings())
    try await store.save(session)
    let segment = TranscriptSegment(sessionID: session.id, source: .file, start: 12, end: 20,
                                    text: "Se acordó comprar dos micrófonos. Ana enviará la cotización el viernes.")
    try await store.append(segment)

    let reply = try await TranscriptAssistant.ask("¿Qué se acordó comprar?", in: session, store: store)
    #expect(reply.text?.localizedCaseInsensitiveContains("micrófonos") == true)
    #expect(reply.evidence.first?.segmentID == segment.id)
    #expect(reply.evidence.first?.start == 12)
    let missing = try await TranscriptAssistant.ask("¿Cuál es el número de pasaporte de Ana?", in: session, store: store)
    #expect(missing.text == nil)
    #expect(missing.evidence.isEmpty)
}
