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
