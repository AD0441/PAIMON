import Foundation
import Testing
@testable import LAICore

@Test func soundEventsMapToTheirTrackWithoutCrossingAnArchivedPause() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = AudioArchive(directory: directory)
    let samples = [Float](repeating: 0.1, count: 16_000)
    try await archive.append(.init(samples: samples, sampleRate: 8_000, start: 1, source: .system))
    try await archive.append(.init(samples: samples, sampleRate: 8_000, start: 3, source: .microphone))
    try await archive.append(.init(samples: samples, sampleRate: 8_000, start: 8, source: .system))
    await archive.close()

    let track = try #require(VocalAudioTrack.archived(in: directory).first { $0.source == .system })
    let windows: [VocalSoundAnalysis.Window] = [
        .init(kind: .laughter, start: 0, end: 1.5),
        .init(kind: .laughter, start: 1, end: 2),
        .init(kind: .applause, start: 1.75, end: 2.75),
        .init(kind: .laughter, start: 2, end: 3.5),
        .init(kind: .applause, start: 3, end: 4)
    ]
    let aligned = try await VocalSoundAnalysis.align(windows, track: track, frameCount: 32_000, rate: 8_000, duration: 10)
    let events = VocalSoundAnalysis.merge(aligned)
    #expect(events.map(\.kind) == [.laughter, .laughter, .applause])
    #expect(events.map(\.start) == [1, 8, 9])
    #expect(events.map(\.end) == [3, 9.5, 10])
    #expect(events.map(\.audioStart) == [0, 2, 3])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_SOUND_FIXTURES"] != nil), .timeLimit(.minutes(1)))
func appleSoundAnalysisRecognizesLaughterAndApplauseAndSkipsSpeech() async throws {
    let directory = try #require(ProcessInfo.processInfo.environment["PAIMON_TEST_SOUND_FIXTURES"])
    let fixtures = URL(fileURLWithPath: directory)
    let speech = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let samples: [(URL, VocalSoundKind?)] = [
        (fixtures.appendingPathComponent("laughter.wav"), .laughter),
        (fixtures.appendingPathComponent("applause.wav"), .applause),
        (speech, nil)
    ]
    for (url, expected) in samples {
        let report = try await VocalSoundAnalysis.analyze(track: VocalAudioTrack(importedAudio: url), sessionDuration: 0)
        if let expected {
            #expect(report.events.contains { $0.kind == expected })
            #expect(report.events.allSatisfy { $0.kind == expected && $0.end > $0.start && $0.start == $0.audioStart })
        } else {
            #expect(report.events.isEmpty)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func soundCatalogAndFilteringUseTheNativeModel() async throws {
    let categories = try await VocalSoundAnalysis.availableIdentifiers()
    #expect(categories.count > 100)
    #expect(categories.contains("speech"))
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let track = VocalAudioTrack(importedAudio: fixture)
    let report = try await VocalSoundAnalysis.analyze(track: track, sessionDuration: 0, identifiers: ["speech"])
    #expect(!report.events.isEmpty)
    #expect(report.events.allSatisfy { $0.kind == .other("speech") })
    let filtered = try await VocalSoundAnalysis.analyze(track: track, sessionDuration: 0, identifiers: ["applause"])
    #expect(filtered.events.isEmpty)
}
