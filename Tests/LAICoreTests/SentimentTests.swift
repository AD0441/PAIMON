import Foundation
import FoundationModels
import NaturalLanguage
import Testing
@testable import LAICore

@Test func applePolaritiesUseNativeScoresAndPreserveMissingValues() throws {
    #expect(TextPolarity.score("", language: .english) == nil)
    #expect(TextPolarity.score("texto", language: .undetermined) == nil)
    let spanish = "Me encantó el resultado de la reunión y quedé muy satisfecho."
    #expect(TextPolarity.language(of: spanish, fallback: Locale(identifier: "es-CL")) == .spanish)
    if NLTagger.availableTagSchemes(for: .paragraph, language: .spanish).contains(.sentimentScore) {
        let positive = try #require(TextPolarity.score(spanish, language: .spanish))
        let negative = try #require(TextPolarity.score("Odié el resultado. Fue terrible y me decepcionó muchísimo.", language: .spanish))
        #expect(positive > negative)
    } else {
        #expect(TextPolarity.score(spanish, language: .spanish) == nil)
    }
    if NLTagger.availableTagSchemes(for: .paragraph, language: .english).contains(.sentimentScore) {
        let positive = try #require(TextPolarity.score("I loved this excellent result and I am very happy.", language: .english))
        let neutral = try #require(TextPolarity.score("The meeting is scheduled for Monday at ten.", language: .english))
        let negative = try #require(TextPolarity.score("This was an awful result and I hated every minute of it.", language: .english))
        #expect(positive > neutral && neutral > negative)
        #expect((-1...1).contains(positive) && (-1...1).contains(neutral) && (-1...1).contains(negative))
    }
}

@Test func longExcerptsRemainBoundedAndRetainTheirText() {
    let sentence = "No estoy de acuerdo con el cambio. Propongo revisar los resultados antes de decidir."
    let source = Array(repeating: sentence, count: 160).joined(separator: " ")
    let excerpts = SentimentAnalyzer.excerpts(source)
    #expect(excerpts.count > 1)
    #expect(excerpts.allSatisfy { $0.count <= 650 })
    #expect(excerpts.joined(separator: " ") == source)
    #expect(SentimentAnalyzer.excerpts(" \n ").isEmpty)
    let points = (0..<250).map { point($0, score: nil) }
    let report = TranscriptSentiment(points: points, tagging: .unavailable, tagged: 0)
    #expect(report.tagTargets().count == 48)
    #expect(report.tagTargets().first == 0)
    #expect(report.tagTargets().last == 249)
}

private func point(_ index: Int, score: Double?, time: Double? = nil, emotions: [String] = [], context: [String] = []) -> SentimentPoint {
    SentimentPoint(id: index, segmentID: "file-\(index)", time: time, excerpt: "Prueba", speaker: nil,
                   speakerNumber: nil, score: score, emotions: emotions, context: context)
}

@Test func momentsUseChangesWithoutBridgingAbsentScores() {
    let report = TranscriptSentiment(points: [
        point(0, score: 0.8, time: 0, context: ["presupuesto"]),
        point(1, score: -0.2, time: 12, emotions: ["preocupación"], context: ["presupuesto"]),
        point(2, score: nil),
        point(3, score: 0.5, time: 24),
        point(4, score: -0.1, time: 40)
    ], tagging: .complete, tagged: 2)
    #expect(!report.usesTime)
    #expect(report.moments().map(\.id) == [0, 1, 4])
    #expect(report.moments().map(\.reason) == [.positive, .topicChange, .change])
    #expect(report.emotionCounts.first?.tag == "preocupación")
}

@Test func cachePersistsAndInvalidatesWhenTranscriptChanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Prueba", settings: AppSettings())
    session.status = "completed"
    try await store.save(session)
    let segment = TranscriptSegment(sessionID: session.id, source: .file, start: 0, end: 5, text: "Me preocupa el retraso.")
    try await store.append(segment)
    let stamp = try await store.sentimentStamp(session: session.id)
    let report = TranscriptSentiment(points: [point(0, score: -0.5)], tagging: .unavailable, tagged: 0)
    try await store.saveSentiment(report, session: session.id, stamp: stamp)
    let reopened = try SessionStore(directory: directory)
    #expect(try await reopened.cachedSentiment(session: session.id)?.points.first?.score == -0.5)
    _ = try await reopened.correctSegment(session: session.id, id: segment.id, text: "No estoy de acuerdo.")
    #expect(try await store.cachedSentiment(session: session.id) == nil)
    await #expect(throws: LAIError.self) {
        try await store.saveSentiment(report, session: session.id, stamp: stamp)
    }
}

@Test func emptyTranscriptsHaveNoInventedScoresOrTags() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Vacía", settings: AppSettings())
    session.status = "completed"
    try await store.save(session)
    let report = try await SentimentAnalyzer.analyze(session: session, store: store)
    let model = SystemLanguageModel(useCase: .contentTagging)
    #expect(report.tagging == (model.isAvailable ? .complete : .unavailable))
    #expect(report.points.isEmpty && report.tagged == 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_SENTIMENT_FOUNDATION"] == "1"), .timeLimit(.minutes(1)))
func nativeTaggingDistinguishesConcernAndDisagreement() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Prueba Chile", settings: AppSettings())
    session.settings.locale = "es-CL"
    session.status = "completed"
    try await store.save(session)
    try await store.append(.init(sessionID: session.id, source: .file, start: 0, end: 5,
                                text: "Me preocupa mucho que todavía no tengamos respuesta. Eso puede atrasar el proyecto."))
    try await store.append(.init(sessionID: session.id, source: .file, start: 5, end: 10,
                                text: "No estoy de acuerdo con mover la reunión. Propongo que mantengamos el horario original."))
    let report = try await SentimentAnalyzer.analyze(session: session, store: store)
    let model = SystemLanguageModel(useCase: .contentTagging)
    if !model.isAvailable {
        #expect(report.tagging == .unavailable)
        #expect(report.tagged == 0)
    } else if !model.supportsLocale(Locale(identifier: "es-CL")) {
        #expect(report.tagging == .unsupported)
        #expect(report.tagged == 0)
    } else {
        #expect(report.tagged == 2)
        #expect(!report.points[0].emotions.isEmpty)
        let labels = report.points.flatMap(\.emotions)
        #expect(!labels.contains { $0.contains("enojo") || $0.contains("ira") || $0.contains("rabia") })
    }
}

private struct DisabledSentimentTagger: SentimentTagging {
    let isAvailable: Bool
    func supportsLocale(_ locale: Locale) -> Bool { false }
    func tags(for text: String) async throws -> (emotions: [String], context: [String]) {
        Issue.record("El etiquetador no debió recibir texto")
        return ([], [])
    }
}

@Test(arguments: [false, true])
func localScoresSurviveWhenEmotionTaggingCannotRun(_ isAvailable: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var session = Session(title: "Prueba", settings: AppSettings())
    session.status = "completed"
    try await store.save(session)
    let text = "I am very happy with the excellent result."
    try await store.append(.init(sessionID: session.id, source: .file, start: 0, end: 3, text: text))
    let report = try await SentimentAnalyzer.analyze(session: session, store: store,
                                                    tagger: DisabledSentimentTagger(isAvailable: isAvailable))
    #expect(report.tagging == (isAvailable ? .unsupported : .unavailable))
    #expect(report.tagged == 0)
    #expect(report.points.count == 1)
    #expect(report.points.first?.score == TextPolarity.score(text, language: .english))
    #expect(report.points.first?.emotions == [])
    #expect(try await store.cachedSentiment(session: session.id)?.tagging == report.tagging)
}
