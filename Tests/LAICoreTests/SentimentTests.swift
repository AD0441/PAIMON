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
    #expect(report.moments().map(\.previousScore) == [nil, 0.8, 0.5])
    #expect(report.emotionCounts.first?.tag == "preocupación")
}

@Test func concentrationUsesExactAppleScoresAndExcludesMissingValues() {
    let scores: [Double?] = [-1, -1, -1, -0.99, 0.2, nil, nil]
    let points = scores.enumerated().map { point($0.offset, score: $0.element) }
    let report = TranscriptSentiment(points: points, tagging: .unavailable, tagged: 0)
    #expect(report.boundaryConcentration?.score == -1)
    #expect(report.boundaryConcentration?.count == 3)
    #expect(report.boundaryConcentration?.total == 5)
    let smallSample = TranscriptSentiment(points: Array(points.prefix(4)), tagging: .unavailable, tagged: 0)
    #expect(smallSample.boundaryConcentration == nil)
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
    let model = SystemLanguageModel.default
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
    let model = SystemLanguageModel.default
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
    func assess(_ texts: [String], locale: Locale) async throws -> [SentimentAssessment?] {
        Issue.record("El etiquetador no debió recibir texto")
        return []
    }
}

@Test(arguments: [false, true])
func rawScoresRemainAuditableWhenLocalClassificationCannotRun(_ isAvailable: Bool) async throws {
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
    #expect(report.points.first?.score == nil)
    #expect(report.points.first?.rawAppleScore == TextPolarity.score(text, language: .english))
    #expect(report.points.first?.emotions == [])
    #expect(try await store.cachedSentiment(session: session.id)?.tagging == report.tagging)
}

@Test func neutralIsZeroButMissingAndMixedAreNotInventedNeutrality() {
    func assessment(_ polarity: TextSentimentClass) -> SentimentAssessment {
        .init(polarity: polarity, strength: .clear, quote: nil, emotions: [], context: [])
    }
    #expect(assessment(.neutral).score == 0)
    #expect(assessment(.uncertain).score == nil)
    #expect(assessment(.mixed).score == nil)
    #expect(assessment(.positive).score! > 0)
    #expect(assessment(.negative).score! < 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_POLARITY"] == "1"), .timeLimit(.minutes(3)), arguments: ["es-ES", "en-US"])
func nativeLocalPolaritySeparatesFactsFromExplicitEvaluations(_ locale: String) async throws {
    let texts = locale.hasPrefix("es") ? ["La reunión empieza a las diez.", "La propuesta tiene tres etapas.",
                 "Acordamos comprar dos micrófonos para el laboratorio.", "El plazo de entrega aumentó tres días.",
                 "Me alegra mucho este excelente resultado.", "Estoy satisfecho con el trabajo del equipo.",
                 "Estoy muy decepcionado, el resultado es pésimo.", "No estoy satisfecho con el resultado."] :
                ["The meeting starts at ten.", "The proposal has three stages.",
                 "We decided to buy two microphones for the laboratory.", "The delivery time increased by three days.",
                 "I am very happy with this excellent result.", "I am satisfied with the team's work.",
                 "I am disappointed; this result is terrible.", "I am not happy with this result."]
    let output = try await LocalSentimentClassifier().assess(texts, locale: Locale(identifier: locale))
    #expect(output.count == texts.count)
    for index in 0..<4 {
        #expect(output[index]?.polarity == .neutral && output[index]?.score == 0)
        #expect(output[index]?.emotions.isEmpty == true)
    }
    for index in [4, 5] { #expect((output[index]?.score ?? -1) > 0) }
    for index in [6, 7] { #expect((output[index]?.score ?? 1) < 0) }
}

private actor CountingSentimentTagger: SentimentTagging {
    nonisolated var isAvailable: Bool { true }
    nonisolated func supportsLocale(_ locale: Locale) -> Bool { true }
    private(set) var calls=0
    func assess(_ texts:[String],locale:Locale) async throws -> [SentimentAssessment?] {
        calls += 1
        return texts.map { _ in .init(polarity:.neutral,strength:.mild,quote:nil,emotions:[],context:[]) }
    }
}

@Test func sentimentBatchesStayBoundedAndDoNotGenerateOncePerField() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Muestreo sintético",settings:AppSettings()); session.status="completed"
    try await store.save(session)
    for index in 0..<200 {
        try await store.append(.init(sessionID:session.id,source:.file,start:Double(index*6),end:Double(index*6+5),text:"El informe tiene tres secciones."))
    }
    let tagger=CountingSentimentTagger()
    let result=try await SentimentAnalyzer.analyze(session:session,store:store,tagger:tagger)
    #expect(result.points.count==200)
    #expect(result.tagged==48)
    #expect(result.points.filter{$0.score==0}.count==48)
    #expect(result.points.filter{$0.score==nil}.count==152)
    #expect(await tagger.calls==16)
}

@Test func reusedNativeScorerPreservesScoresAcrossLanguagesWithoutSharedState() throws {
    let inputs:[(String,NLLanguage)] = [("La reunión empieza a las diez.",.spanish),
        ("I am very happy with the excellent result.",.english),
        ("No estoy satisfecho con el resultado.",.spanish),("The proposal has three stages.",.english)]
    let examples=Array(repeating:inputs,count:25).flatMap{$0}
    let started=ProcessInfo.processInfo.systemUptime
    let independent=examples.map{TextPolarity.score($0.0,language:$0.1)}
    let independentSeconds=ProcessInfo.processInfo.systemUptime-started
    let scorer=NativePolarityScorer()
    let reusedStart=ProcessInfo.processInfo.systemUptime
    let reused=examples.map{scorer.score($0.0,language:$0.1)}
    let reusedSeconds=ProcessInfo.processInfo.systemUptime-reusedStart
    #expect(independent==reused)
    #expect(scorer.score("",language:.english)==nil)
    #expect(scorer.score("Información",language:.undetermined)==nil)
    if let path=ProcessInfo.processInfo.environment["PAIMON_POLARITY_SCORER_REPORT"] {
        let report:[String:Any]=["synthetic":true,"excerpts":examples.count,"equivalentScores":independent==reused,
            "independentTaggerSeconds":independentSeconds,"reusedTaggerSeconds":reusedSeconds,
            "note":"Single serial microbenchmark, independent run first. Not an end-to-end memory, inference or battery benchmark."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
    }
}

@Test func structuredPolarityEncodesUnknownAsNullAndNeutralAsAnActualZero() throws {
    let missing=point(0,score:nil)
    let neutral=point(1,score:0)
    let values=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode([missing,neutral])) as? [[String:Any]])
    #expect(values[0]["score"] is NSNull)
    #expect(values[1]["score"] as? Double == 0)
    #expect(try JSONDecoder().decode([SentimentPoint].self,from:JSONEncoder().encode([missing,neutral])).map(\.score)==[nil,0])
}

private actor FailingSentimentTagger: SentimentTagging {
    nonisolated var isAvailable: Bool { true }
    nonisolated func supportsLocale(_ locale: Locale) -> Bool { true }
    private(set) var calls=0
    func assess(_ texts:[String],locale:Locale) async throws -> [SentimentAssessment?] {
        calls += 1; throw LAIError.message("Respuesta incompleta sintética")
    }
}

@Test func repeatedModelFailuresStopWithoutInventingScoresOrRetryingEveryFragment() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Fallo controlado",settings:AppSettings()); session.status="completed"
    try await store.save(session)
    for index in 0..<48 {
        try await store.append(.init(sessionID:session.id,source:.file,start:Double(index*6),end:Double(index*6+5),text:"El informe tiene tres secciones."))
    }
    let tagger=FailingSentimentTagger()
    let result=try await SentimentAnalyzer.analyze(session:session,store:store,tagger:tagger)
    #expect(await tagger.calls==3)
    #expect(result.tagging == .partial && result.tagged==0)
    #expect(result.points.allSatisfy{$0.score==nil && $0.polarity==nil})
    #expect(try await store.cachedSentiment(session:session.id)?.points.count==48)
}
