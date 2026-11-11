import Foundation
import Testing
@testable import LAICore

@Test func vocalEmotionUsesNativeClassOrderAndDeclinesAmbiguousOutput() {
    #expect(VocalEmotionAnalysis.estimate([0, 0, 0, 0.8, 0.2, 0, 0, 0, 0])?.emotion == .joy)
    #expect(VocalEmotionAnalysis.estimate([0, 0, 0, 0.48, 0.47, 0, 0.05, 0, 0]) == nil)
    #expect(VocalEmotionAnalysis.estimate([0, 0, 0, 0.1, 0.1, 0.8, 0, 0, 0]) == nil)
    #expect(VocalEmotionAnalysis.estimate([0, 0, 0, 0, 0, 0, 0, 0, .nan]) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_VOICE_MODEL"] != nil), .timeLimit(.minutes(1)))
func emotion2vecProcessesTheSpanishAudioFixtureThroughCoreML() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PAIMON_TEST_VOICE_MODEL"])
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let report = try await VocalEmotionAnalysis.analyze(
        track: VocalAudioTrack(importedAudio: fixture), sessionDuration: 0, packageDirectory: URL(fileURLWithPath: path))
    #expect(report.points.count >= 2)
    #expect(report.points.first?.start == 0)
    #expect(report.points.allSatisfy { $0.end > $0.start && $0.end - $0.start <= 3.001 && $0.audioStart == $0.start })
    #expect(report.points.contains { $0.emotion == .neutral })
}

@Test func threeVocalModelsPreserveTheirClassOrdersAndOldPreferences() throws {
    #expect(VocalEmotionAnalysis.estimate([0.9, 0.02, 0.04, 0.04], choice: .superb)?.emotion == .neutral)
    #expect(VocalEmotionAnalysis.estimate([0.02, 0.02, 0.94, 0.02], choice: .superb)?.emotion == .anger)
    #expect(VocalEmotionAnalysis.estimate([0.9, 0.02, 0.04, 0.04], choice: .large) == nil)
    #expect(VocalEmotionModel.base.embeddingDimension == nil)
    #expect(Set(VocalEmotionModel.allCases.map(\.package)).count == 3)
    let old = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(AppSettings()))
    #expect((old.vocalEmotionModel ?? .base) == .base)
}

@Test func vocalEmbeddingsAreVectorsRatherThanEmotionalProbabilities() {
    #expect(VocalEmbeddingAnalysis.cosine([1, 0], [1, 0]) == 1)
    #expect(VocalEmbeddingAnalysis.cosine([1, 0], [0, 1]) == 0)
    #expect(VocalEmbeddingAnalysis.cosine([1, 0], [-1, 0]) == -1)
    #expect(VocalEmbeddingAnalysis.cosine([0, 0], [1, 0]) == nil)
    #expect(VocalEmbeddingAnalysis.cosine([.nan, 0], [1, 0]) == nil)
    #expect(VocalEmbeddingAnalysis.cosine([1], [1, 0]) == nil)
}

@Test func vocalChangesDistinguishSpeakersAndDoNotBridgeSilentWindows() async throws {
    func point(_ time: Double, _ embedding: [Float]?) -> VocalEmotionPoint {
        VocalEmotionPoint(start: time, end: time + 3, audioStart: time, audioEnd: time + 3,
                          emotion: .neutral, confidence: 0.9, embedding: embedding)
    }
    let report = VocalEmotionReport(points: [point(0, [1, 0]), point(3, [0, 1]), point(6, nil),
                                            point(9, [1, 0])], sampled: false, model: .superb)
    let changes = try await VocalEmbeddingAnalysis.changes(in: report, threshold: 0.2, speakers: [0: "A", 3: "B"])
    #expect(changes.count == 1)
    #expect(changes.first?.speakerChanged == true)
    #expect(changes.first?.start == 3)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_EXTENDED_VOICE_MODELS"] != nil), .timeLimit(.minutes(3)))
func additionalVocalModelsRunThroughCoreMLWithRealEmbeddings() async throws {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["PAIMON_TEST_EXTENDED_VOICE_MODELS"]))
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    for choice in [VocalEmotionModel.superb, .large] {
        let report = try await VocalEmotionAnalysis.analyze(track: .init(importedAudio: fixture), sessionDuration: 6,
            choice: choice, embeddings: true, packageDirectory: root)
        #expect(report.model == choice)
        #expect(!report.points.isEmpty)
        let vector = try #require(report.points.compactMap(\.embedding).first)
        #expect(vector.count == choice.embeddingDimension)
        #expect(vector.allSatisfy { $0.isFinite })
        #expect(abs((VocalEmbeddingAnalysis.cosine(vector, vector) ?? 0) - 1) < 0.00001)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_VOCAL_DOWNLOADS"] == "1"), .timeLimit(.minutes(10)))
func managedVocalDownloadsVerifyAndInstallThePublishedPackages() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    for choice in [VocalEmotionModel.large,.superb] {
        let destination=root.appendingPathComponent(choice.rawValue)
        let installed=try await choice.package.download(to:destination) { _ in }
        #expect(FileManager.default.fileExists(atPath:installed.appendingPathComponent(choice.folder).path))
        #expect(FileManager.default.fileExists(atPath:installed.appendingPathComponent(choice == .large ? "EmotionLarge-LICENSE.txt":"Wav2VecSuperb-LICENSE.txt").path))
    }
}
