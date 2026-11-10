import AVFoundation
import Foundation

public struct SpeakerTurn: Codable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

public struct SessionSpeaker: Identifiable, Sendable, Equatable {
    public let id: String
    public let number: Int
    public let name: String?
}

/// Each source keeps its own timeline and speaker IDs. Audio is retained only
/// for the current model window, then sent to the optional offline worker.
actor DiarizationSession {
    private struct Window {
        let converter = PCMStreamConverter()
        var samples: [Float] = []
        var start: Double
        var expected: Double
    }

    private struct Response: Decodable {
        var turns: [SpeakerTurn]?
        var error: String?
    }

    private static let sampleRate = 16_000.0
    private static let windowSize = 160_000
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    private var windows: [AudioSource: Window] = [:]
    private let worker = LocalWorker()
    private let executable: String
    private let models: String
    private let sessionID: UUID
    private let store: SessionStore
    private let events: AsyncStream<PipelineEvent>.Continuation
    private var started = false
    private var closed = false

    init?(settings: AppSettings, sessionID: UUID, store: SessionStore, events: AsyncStream<PipelineEvent>.Continuation) {
        guard settings.diarizationEnabled == true else { return nil }
        executable = OptionalModelPackage.fluidWorker(configured:settings.fluidWorker) ?? ""
        models = settings.diarizationModels ?? (OptionalModelPackage.diarization.installed ? OptionalModelPackage.diarization.directory.path : "")
        self.sessionID = sessionID
        self.store = store
        self.events = events
    }

    func append(_ chunk: AudioChunk) async {
        guard !closed, !Task.isCancelled, !chunk.samples.isEmpty else { return }
        do {
            if !started {
                guard !models.isEmpty, !executable.isEmpty else {
                    throw LAIError.message("Abre Ajustes → Modelos para preparar la separación de voces.")
                }
                try await worker.start(executable: executable, arguments: ["--diarize", models])
                started = true
            }
            var window = windows.removeValue(forKey: chunk.source) ?? Window(start: chunk.start, expected: chunk.start)
            // A pause or dropped audio must never compress the source timeline.
            if abs(chunk.start - window.expected) > 0.12 {
                try await infer(window.samples[...], start: window.start, source: chunk.source)
                window = Window(start: chunk.start, expected: chunk.start)
            }
            let converted = try window.converter.buffer(chunk, format: format)
            if let channel = converted.floatChannelData?[0] {
                window.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            }
            window.expected = chunk.start + Double(chunk.samples.count) / chunk.sampleRate
            while window.samples.count >= Self.windowSize {
                try await infer(window.samples.prefix(Self.windowSize), start: window.start, source: chunk.source)
                window.samples.removeFirst(Self.windowSize)
                window.start += Double(Self.windowSize) / Self.sampleRate
            }
            windows[chunk.source] = window
        } catch {
            await fail(error)
        }
    }

    func finish() async {
        guard !closed else { return }
        do {
            for source in AudioSource.allCases {
                guard var window = windows.removeValue(forKey: source) else { continue }
                if let tail = try window.converter.flush(), let channel = tail.floatChannelData?[0] {
                    // AVAudioConverter can add filter padding at EOF.
                    let remaining = max(0, Int(((window.expected - window.start) * Self.sampleRate).rounded()) - window.samples.count)
                    window.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: min(Int(tail.frameLength), remaining)))
                }
                try await infer(window.samples.prefix(Self.windowSize), start: window.start, source: source)
            }
        } catch {
            await fail(error)
        }
        await cancel()
    }

    func cancel() async {
        closed = true
        windows.removeAll()
        await worker.stop()
    }

    private func fail(_ error: any Error) async {
        if !Task.isCancelled {
            events.yield(.warning("Diarización interrumpida. La transcripción continúa. \(error.localizedDescription)"))
        }
        await cancel()
    }

    private func infer(_ samples: ArraySlice<Float>, start: Double, source: AudioSource) async throws {
        try Task.checkCancellation()
        guard samples.count >= 4_800, samples.contains(where: { abs($0) > 0.001 }) else { return }
        let duration = Double(samples.count) / Self.sampleRate
        let pcm = samples.withUnsafeBytes { Data($0).base64EncodedString() }
        let request = try JSONEncoder().encode(["pcm": pcm, "source": source.rawValue])
        let data = try await worker.request(request, timeout: 30)
        try Task.checkCancellation()
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let turns = response.turns else { throw LAIError.message(response.error ?? "Respuesta de diarización inválida.") }
        let aligned = turns.compactMap { turn -> SpeakerTurn? in
            guard turn.start.isFinite, turn.end.isFinite, !turn.speaker.isEmpty else { return nil }
            let begin = max(0, turn.start)
            let end = min(duration, turn.end)
            guard end > begin else { return nil }
            return SpeakerTurn(speaker: "\(source.rawValue):\(turn.speaker)", start: start + begin, end: start + end)
        }
        if !aligned.isEmpty {
            try await store.appendSpeakerTurns(aligned, source: source, session: sessionID)
            events.yield(.speakersUpdated(sessionID))
        }
    }
}
