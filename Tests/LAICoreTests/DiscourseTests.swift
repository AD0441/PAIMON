import Foundation
import FoundationModels
import PDFKit
import Testing
@testable import LAICore

private func discourseSource(_ session: Session, text: String, time: Double = 0) -> DiscourseAnalyzer.Source {
    let segment = TranscriptSegment(sessionID: session.id, source: .file, start: time, end: time + 5, text: text)
    return .init(sequence: Int64(time + 1), part: 0, lastPart: true, segment: segment, text: text)
}
private func discourseItem(kind: DiscourseKind, text: String, quote: String,
                           source: String = "F1", target: String = "") -> DiscourseDraftItem {
    .init(citations: [.init(source: DiscourseSourceKey(rawValue:source)!, quote: quote)],
          kind: kind, statement: text, topic: "Micrófonos", parentTopic: "Laboratorio",
          target: DiscourseTargetKey(rawValue:target.isEmpty ? "none":target)!)
}

@Test func discourseRejectsInventedSourcesAndDoesNotInferAbandonmentFromSilence() {
    let session = Session(title: "Discurso sintético", settings: AppSettings())
    let source = discourseSource(session, text: "Propongo comprar dos micrófonos. Cambiemos de tema.")
    let proposal = discourseItem(kind: .proposal, text: "Comprar dos micrófonos", quote: "Propongo comprar dos micrófonos.")
    let abandoned = discourseItem(kind: .evolution, text: "Se abandona comprar micrófonos", quote: "Cambiemos de tema.", target: "U1")
    let invented = discourseItem(kind: .argument, text: "Los micrófonos fallan", quote: "Los micrófonos fallan")
    let unknown = discourseItem(kind: .topic, text: "Micrófonos", quote: "Propongo comprar", source: "F8")
    let values = DiscourseAnalyzer.verified(.init(items: [proposal, abandoned, invented, unknown]), sources: [source], prior: [])
    #expect(values.count == 1)
    #expect(values.first?.kind == .proposal)
    #expect(!DiscourseAnalyzer.explicitEvolution(.accepts, quote: "Si aprobamos los micrófonos, avisaremos."))
    #expect(!DiscourseAnalyzer.explicitEvolution(.accepts, quote: "No aprobamos comprar los micrófonos."))
}

@Test func discourseLinksExplicitEvolutionAndResponsesToExistingEvidence() {
    let session = Session(title: "Discurso sintético", settings: AppSettings())
    let first = discourseSource(session, text: "Propongo comprar dos micrófonos.")
    let proposal = DiscourseAnalyzer.verified(.init(items: [
        discourseItem(kind: .proposal, text: "Comprar dos micrófonos", quote: first.text)
    ]), sources: [first], prior: [])
    let next = discourseSource(session, text: "Aprobamos comprar los micrófonos.", time: 10)
    let values = DiscourseAnalyzer.verified(.init(items: [
        discourseItem(kind: .evolution, text: "Se acepta comprar micrófonos", quote: next.text, target: "P1")
    ]), sources: [next], prior: proposal)
    #expect(values.count == 1)
    #expect(values.first?.target == proposal.first?.id)
    #expect(values.first?.relation == .accepts)
    #expect(values.first?.evidence.first?.start == 10)
}

@Test func discourseParticipationMergesWindowsWithoutCountingOverlapsOrPausesAsSpeech() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    let session = Session(title: "Participación", settings: AppSettings())
    try await store.save(session)
    try await store.appendSpeakerTurns([
        .init(speaker: "A", start: 0, end: 5), .init(speaker: "A", start: 4, end: 8),
        .init(speaker: "A", start: 8.1, end: 9), .init(speaker: "A", start: 15, end: 18)
    ], source: .system, session: session.id)
    try await store.appendSpeakerTurns([.init(speaker: "A", start: 0, end: 4)], source: .microphone, session: session.id)
    let values = try await store.participation(session: session.id)
    let system = try #require(values.first { $0.source == .system })
    #expect(abs(system.seconds - 11.9) < 0.001)
    #expect(system.turns == 2)
    #expect(abs(system.longestTurn - 8.9) < 0.001)
    #expect(values.count == 2)
}

@Test func discourseCheckpointRejectsStaleEvidenceAndDeletesWithTheSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Discurso", settings: AppSettings()); session.status = "completed"
    try await store.save(session)
    let source = discourseSource(session, text: "Propongo comprar dos micrófonos.")
    try await store.append(source.segment)
    let findings = DiscourseAnalyzer.verified(.init(items: [
        discourseItem(kind: .proposal, text: "Comprar micrófonos", quote: source.text)
    ]), sources: [source], prior: [])
    let upper = try await store.lastTranscriptRow(session: session.id)
    let stamp = DiscourseAnalyzer.stamp(session: session, revision: 0)
    try await store.commitDiscourse(findings, session: session, stamp: stamp, revision: 0, through: upper, final: true, rejected: 0)
    #expect(try await store.discourseState(session: session.id)?.final == true)
    #expect(try await store.discourseTopics(session: session.id).first?.title == "Micrófonos")
    #expect(try await store.discourseContext(session: session.id, terms: []).count == 1)
    var options = ExportOptions(); options.kinds = []; options.discourse = true
    try await SessionExporter(store: store).export(session: session, to: directory.appendingPathComponent("discourse.json"), format: .json, options: options)
    let content = try String(contentsOf: directory.appendingPathComponent("discourse.json"), encoding: .utf8)
    #expect(content.contains("\"discourse\""))
    #expect(content.contains(findings[0].id))
    _ = try await store.correctSegment(session: session.id, id: source.segment.id, text: "Texto revisado.")
    await #expect(throws: (any Error).self) {
        try await store.commitDiscourse(findings, session: session, stamp: stamp, revision: 0, through: upper, final: true, rejected: 0)
    }
    try await store.requestFinalDiscourse(session: session.id)
    try await store.delete(session: session.id)
    #expect(try await store.discourseFindings(session: session.id).isEmpty)
    #expect(try await store.discourseState(session: session.id) == nil)
    #expect(try await store.pendingDiscourseSession() == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_DISCOURSE"] == "1"), .timeLimit(.minutes(3)))
func discourseNativeModelProcessesProposalsAndKeepsItsCheckpoint() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Reunión sintética", settings: AppSettings()); session.status = "recording"
    try await store.save(session)
    for (index, text) in ["Propongo comprar dos micrófonos para el laboratorio.",
                          "Los micrófonos actuales fallan y necesitamos grabar las clases."].enumerated() {
        try await store.append(discourseSource(session, text: text, time: Double(index * 6)).segment)
    }
    try await DiscourseAnalyzer.analyze(session: session, store: store, final: false)
    let provisional = try await store.discourseFindings(session: session.id)
    #expect(provisional.contains { $0.kind == .proposal })
    #expect(try await store.discourseState(session: session.id)?.final == false)
    try await store.append(discourseSource(session, text: "Aprobamos comprar los dos micrófonos para el laboratorio.", time: 20).segment)
    session.status = "completed"; try await store.save(session)
    try await DiscourseAnalyzer.analyze(session: session, store: store, final: true)
    let first = try await store.discourseFindings(session: session.id)
    #expect(first.allSatisfy { !$0.evidence.isEmpty })
    #expect(first.contains { $0.kind == .evolution && $0.relation == .accepts })
    #expect(try await store.discourseState(session: session.id)?.final == true)
    try await DiscourseAnalyzer.analyze(session: session, store: store, final: true)
    #expect(try await store.discourseFindings(session: session.id).map(\.id) == first.map(\.id))
}


@Test func discourseIncrementalCheckpointPreservesEarlierResultsAndFinalizesOnlyCompletedSessions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Discurso incremental", settings: AppSettings()); session.status = "recording"
    try await store.save(session)
    let source = discourseSource(session, text: "Propongo comprar dos micrófonos.")
    try await store.append(source.segment)
    let stamp = DiscourseAnalyzer.stamp(session: session, revision: 0)
    let first = DiscourseAnalyzer.verified(.init(items: [discourseItem(kind: .proposal, text: "Comprar micrófonos", quote: source.text)]), sources: [source], prior: [])
    let firstRow = try await store.lastTranscriptRow(session: session.id)
    try await store.commitDiscourse(first, session: session, stamp: stamp, revision: 0, through: firstRow, final: true, rejected: 0)
    #expect(try await store.discourseState(session: session.id)?.final == false)
    let next = discourseSource(session, text: "Aprobamos comprar los micrófonos.", time: 20)
    try await store.append(next.segment)
    let evolution = DiscourseAnalyzer.verified(.init(items: [discourseItem(kind: .evolution, text: "Se acepta la compra", quote: next.text, target: "P1")]), sources: [next], prior: first)
    let lastRow = try await store.lastTranscriptRow(session: session.id)
    session.status = "completed"; try await store.save(session)
    try await store.commitDiscourse(evolution, session: session, stamp: stamp, revision: 0, through: lastRow, final: true, rejected: 0)
    let stored = try await store.discourseFindings(session: session.id)
    #expect(stored.count == 2)
    #expect(try await store.discourseState(session: session.id)?.final == true)
    #expect(try await store.discourseRelated(session: session.id, target: first[0].id).first?.id == evolution.first?.id)
    var options = ExportOptions(); options.kinds = []; options.discourse = true; options.evidence = true
    for format in [ExportFormat.txt, .markdown, .pdf] {
        let url = directory.appendingPathComponent("report." + format.rawValue)
        try await SessionExporter(store: store).export(session: session, to: url, format: format, options: options)
        let text: String
        if format == .pdf { text = try #require(PDFDocument(url: url)?.string) }
        else { text = try String(contentsOf: url, encoding: .utf8) }
        #expect(text.contains("Comprar micrófonos"))
        #expect(text.contains("Aprobamos comprar los micrófonos."))
    }
    var edited = session; edited.context = .init(objective: "Otro objetivo")
    try await store.save(edited)
    await #expect(throws: (any Error).self) {
        try await store.commitDiscourse([], session: session, stamp: stamp, revision: 0, through: lastRow, final: true, rejected: 0)
    }
}

@Test func discourseExplicitQuoteDisambiguatesStateAndRejectsConflictingClauses() {
    let session = Session(title: "Evolución", settings: AppSettings())
    let first = discourseSource(session, text: "Propongo comprar dos micrófonos.")
    let proposal = DiscourseAnalyzer.verified(.init(items: [discourseItem(kind: .proposal, text: "Comprar micrófonos", quote: first.text)]), sources: [first], prior: [])
    let accepted = discourseSource(session, text: "Aprobamos comprar los micrófonos.", time: 10)
    let values = DiscourseAnalyzer.verified(.init(items: [discourseItem(kind: .evolution, text: "Se aprueba la compra", quote: accepted.text, target: "P1")]), sources: [accepted], prior: proposal)
    #expect(values.count == 1)
    #expect(values.first?.relation == .accepts)
    let conflicting = discourseSource(session, text: "Aprobamos comprar micrófonos pero descartamos otras compras.", time: 20)
    let ambiguous = DiscourseAnalyzer.verified(.init(items: [discourseItem(kind: .evolution, text: "Se modifica la compra", quote: conflicting.text, target: "P1")]), sources: [conflicting], prior: proposal)
    #expect(ambiguous.isEmpty)
}

@Test func discourseDoesNotDisplayInternalReferencesAsTopicNames() {
    let session = Session(title: "Temas", settings: AppSettings())
    let source = discourseSource(session, text: "Propongo comprar dos micrófonos.")
    var item = discourseItem(kind: .proposal, text: "Comprar micrófonos", quote: source.text)
    item.parentTopic = "P1"
    #expect(DiscourseAnalyzer.verified(.init(items: [item]), sources: [source], prior: []).first?.parentTopic == "")
    item.topic = "F1"
    #expect(DiscourseAnalyzer.verified(.init(items: [item]), sources: [source], prior: []).isEmpty)
}
