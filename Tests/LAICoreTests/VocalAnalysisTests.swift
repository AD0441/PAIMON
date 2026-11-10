import AVFoundation
import Foundation
import Testing
@testable import LAICore

@Test func vocalAnalysisReadsAnOriginalFileAndMeasuresPitchAndSilence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("prueba.caf")
    try writeVoiceFixture(url: url)
    let points = try await VocalAnalysis.analyze(track: VocalAudioTrack(importedAudio: url), sessionDuration: 3)
    #expect(points.count == 3)
    let silence = try #require(points.first)
    #expect(silence.pitch == nil)
    #expect(abs(silence.quietSeconds - 1) < 0.01)
    #expect(silence.level <= -79)
    let firstTone = try #require(points.dropFirst().first)
    let secondTone = try #require(points.last)
    let pitch = try #require(firstTone.pitch)
    let higherPitch = try #require(secondTone.pitch)
    #expect(abs(pitch - 200) < 5)
    #expect(abs(higherPitch - 320) < 6)
    #expect(secondTone.level > firstTone.level + 4)
    #expect(abs(secondTone.audioStart - 2) < 0.001)
    #expect(abs(secondTone.audioEnd - 3) < 0.001)
}

@Test func vocalArchiveKeepsIndependentSourcesAndRealPauseTimes() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = AudioArchive(directory: directory)
    let tone = samples(pitch: 200, amplitude: 0.2)
    try await archive.append(.init(samples: tone, sampleRate: 8_000, start: 0, source: .system))
    try await archive.append(.init(samples: samples(pitch: 320, amplitude: 0.2), sampleRate: 8_000, start: 0.5, source: .microphone))
    try await archive.append(.init(samples: tone, sampleRate: 8_000, start: 6, source: .system))
    await archive.close()

    let tracks = VocalAudioTrack.archived(in: directory)
    let system = try #require(tracks.first { $0.source == .system })
    let microphone = try #require(tracks.first { $0.source == .microphone })
    let systemPoints = try await VocalAnalysis.analyze(track: system, sessionDuration: 7)
    let micPoints = try await VocalAnalysis.analyze(track: microphone, sessionDuration: 7)
    #expect(systemPoints.map(\.start) == [0, 6])
    #expect(systemPoints.map(\.audioStart) == [0, 1])
    #expect(micPoints.map(\.start) == [0.5, 1])
    #expect(micPoints.allSatisfy { ($0.pitch ?? 0) > 300 })
}

@Test func vocalEvidenceSelectsOnlyOverlappingTranscriptFromTheSameSource() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    let session = Session(title: "Voz", settings: AppSettings())
    try await store.save(session)
    let system = TranscriptSegment(sessionID: session.id, source: .system, start: 2, end: 3, text: "Audio de sistema.")
    try await store.append(system)
    try await store.append(.init(sessionID: session.id, source: .microphone, start: 2.25, end: 4, text: "Micrófono."))
    let result = try await store.overlappingSegment(session: session.id, source: .system, from: 2, to: 3)
    #expect(result?.id == system.id)
    #expect(try await store.overlappingSegment(session: session.id, source: .system, from: 3, to: 4) == nil)
}

@Test func vocalTimelineKeepsABoundedNumberOfPointsForLongAudio() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let duration = 905
    let url = directory.appendingPathComponent("larga.caf")
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8_000, channels: 1, interleaved: false))
    do {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let chunk = AudioChunk(samples: samples(pitch: 200, amplitude: 0.2), sampleRate: 8_000, start: 0, source: .file)
        let buffer = try PCMConverter.buffer(chunk, format: format)
        for _ in 0..<duration { try file.write(from: buffer) }
    }
    let points = try await VocalAnalysis.analyze(track: VocalAudioTrack(importedAudio: url), sessionDuration: Double(duration))
    #expect(points.count == 453)
    #expect(points.first?.start == 0)
    #expect(points.last?.end == Double(duration))
    #expect(points.allSatisfy { ($0.pitch ?? 0) > 195 && ($0.pitch ?? 0) < 205 })
}

private func writeVoiceFixture(url: URL) throws {
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 8_000, channels: 1, interleaved: false))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    for values in [samples(pitch: 0, amplitude: 0), samples(pitch: 200, amplitude: 0.2), samples(pitch: 320, amplitude: 0.4)] {
        let chunk = AudioChunk(samples: values, sampleRate: 8_000, start: 0, source: .file)
        try file.write(from: PCMConverter.buffer(chunk, format: format))
    }
}

private func samples(pitch: Double, amplitude: Double) -> [Float] {
    (0..<8_000).map { frame in Float(amplitude * sin(2 * .pi * pitch * Double(frame) / 8_000)) }
}
