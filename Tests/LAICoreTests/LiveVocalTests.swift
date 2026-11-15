import AVFoundation
import Foundation
import Testing
@testable import LAICore

@Test func liveVocalSamplerKeepsSourcesSeparateAndDoesNotBridgeCaptureGaps() throws {
    let samples = [Float](repeating: 0.1, count: 16000)
    var sampler = LiveVocalSampler(interval: 30)
    func chunk(_ start: Double, _ source: AudioSource = .system) -> AudioChunk {
        .init(samples: samples, sampleRate: 16000, start: start, source: source)
    }
    #expect(try sampler.append(chunk(0)) == nil)
    #expect(try sampler.append(chunk(1)) == nil)
    #expect(try sampler.append(chunk(0, .microphone)) == nil)
    let completedSystem = try sampler.append(chunk(2))
    let first = try #require(completedSystem)
    #expect(first.source == .system && first.samples.count == 48000 && first.start == 0)
    #expect(try sampler.append(chunk(3)) == nil)
    #expect(try sampler.append(chunk(4, .microphone)) == nil)
    #expect(try sampler.append(chunk(5, .microphone)) == nil)
    let completedMicrophone = try sampler.append(chunk(6, .microphone))
    let microphone = try #require(completedMicrophone)
    #expect(microphone.start == 4)
    #expect(try sampler.append(chunk(30)) == nil)
    sampler.reset()
    #expect(try sampler.append(chunk(32)) == nil)
}

@Test func liveVocalMeasurementsDescribeSignalAndDoNotInventEmotion() {
    let samples = (0..<48000).map { Float(sin(2 * Double.pi * 220 * Double($0) / 16000) * 0.2) }
    let value = LiveVocalAnalysis.measure(samples)
    #expect(value.level > -20 && value.level < -10)
    #expect(abs((value.pitch ?? 0) - 220) < 5)
    #expect(value.quietPercent == 0)
    let quiet = LiveVocalAnalysis.measure([Float](repeating: 0, count: 48000))
    #expect(quiet.pitch == nil)
    #expect(quiet.quietPercent == 100)
}

@Test func liveVocalOptionalInferenceDoesNotWaitBehindAnOccupiedGate() async throws {
    let gate = InferenceGate()
    let entered = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    let running = Task {
        try await gate.perform {
            entered.continuation.yield(())
            for await _ in release.stream { break }
            return 1
        }
    }
    for await _ in entered.stream { break }
    let skipped = try await gate.performIfIdle { 2 }
    #expect(skipped == nil)
    release.continuation.yield(())
    #expect(try await running.value == 1)
    #expect(try await gate.performIfIdle { 3 } == 3)
}

@Test func liveVocalPersistsDerivedResultsWithoutSavingAudioAndDeletesThemWithSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var settings = AppSettings(); settings.vocalLiveEnabled = true; settings.vocalSoundLabels = []
    let session = Session(title: "Voz sintética", settings: settings)
    try await store.save(session)
    let pair = AsyncStream<PipelineEvent>.makeStream()
    let live = LiveVocalSession(session: session.id, settings: settings, store: store, events: pair.continuation, allowModels: false)
    let samples = (0..<48000).map { Float(sin(2 * Double.pi * 220 * Double($0) / 16000) * 0.1) }
    await live.append(.init(samples: samples, sampleRate: 16000, start: 0, source: .system))
    let saved = try await store.liveVocalResults(session: session.id)
    #expect(saved.count == 1)
    #expect(saved[0].emotion == nil && saved[0].deferred)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(session.id.uuidString).path))
    await live.suspend(true)
    await live.append(.init(samples: samples, sampleRate: 16000, start: 30, source: .system))
    #expect(try await store.liveVocalResults(session: session.id).count == 1)
    try await store.delete(session: session.id)
    #expect(try await store.liveVocalResults(session: session.id).isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PAIMON_TEST_LIVE_VOCAL"] == "1"), .timeLimit(.minutes(2)))
func liveVocalNativeSoundStreamAndSelectedCoreMLModelProcessActualBuffers() async throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * 3)))
    try file.read(into: buffer)
    let channel = try #require(buffer.floatChannelData?[0])
    let raw = AudioChunk(samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
                         sampleRate: file.processingFormat.sampleRate, start: 0, source: .system)
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
    let pcm = try PCMConverter.buffer(raw, format: format)
    let mono = try #require(pcm.floatChannelData?[0])
    let samples = Array(UnsafeBufferPointer(start: mono, count: min(48000, Int(pcm.frameLength))))
    var settings = AppSettings(); settings.vocalEmotionEnabled = true; settings.vocalSoundLabels = ["speech"]
    let prediction = try await LiveVocalAnalysis.evaluate(.init(source: .system, start: 0, samples: samples),
        session: UUID(), settings: settings, allowModels: true)
    #expect(!prediction.result.deferred)
    #expect(prediction.result.sounds.contains { $0.identifier == "speech" })
    if OptionalModelPackage.vocalEmotion.installed { #expect(prediction.result.model == .base) }
}

@Test func liveVocalRepeatedAvailableResourceChecksDoNotDiscardAnIncompleteSample() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SessionStore(directory: directory)
    var settings = AppSettings(); settings.vocalLiveEnabled = true; settings.vocalSoundLabels = []
    let session = Session(title: "Recursos disponibles", settings: settings); try await store.save(session)
    let pair = AsyncStream<PipelineEvent>.makeStream()
    let live = LiveVocalSession(session: session.id, settings: settings, store: store, events: pair.continuation, allowModels: false)
    let samples = [Float](repeating: 0.1, count: 16000)
    for second in 0..<3 {
        await live.suspend(false)
        await live.append(.init(samples: samples, sampleRate: 16000, start: Double(second), source: .system))
    }
    #expect(try await store.liveVocalResults(session: session.id).count == 1)
    await live.close()
    await live.append(.init(samples: [Float](repeating: 0.1, count: 48000), sampleRate: 16000, start: 30, source: .system))
    #expect(try await store.liveVocalResults(session: session.id).count == 1)
}
