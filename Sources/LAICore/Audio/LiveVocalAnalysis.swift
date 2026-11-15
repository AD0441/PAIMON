import Accelerate
import AVFoundation
import CoreML
import Foundation
import SoundAnalysis
import Synchronization

public struct LiveVocalSound: Codable, Sendable, Identifiable {
    public var id: String { identifier + "-" + String(start) }
    public let identifier: String
    public let start: Double
    public let end: Double
}

public struct LiveVocalResult: Codable, Sendable, Identifiable {
    public var id: String { source.rawValue + "-" + String(Int((start * 1000).rounded())) }
    public let sessionID: UUID
    public let source: AudioSource
    public let start: Double
    public let end: Double
    public let level: Double
    public let pitch: Double?
    public let quietPercent: Double
    public let model: VocalEmotionModel?
    public let modelIdentifier: String?
    public let emotion: VocalEmotion?
    public let score: Double?
    public var distanceFromPrevious: Double?
    public let sounds: [LiveVocalSound]
    public let deferred: Bool
}

struct LiveVocalWindow: Sendable {
    let source: AudioSource
    let start: Double
    let samples: [Float]
}

struct LiveVocalSampler {
    private struct Pending {
        var start: Double
        var expected: Double
        var samples: [Float] = []
        let converter = PCMStreamConverter()
    }
    private var pending: [AudioSource: Pending] = [:]
    private var next: [AudioSource: Double] = [:]
    let interval: Double
    init(interval: Double) { self.interval = interval.isFinite ? max(10, min(120, interval)) : 30 }

    mutating func reset() { pending = [:] }

    mutating func append(_ chunk: AudioChunk) throws -> LiveVocalWindow? {
        guard !chunk.samples.isEmpty, chunk.start.isFinite, chunk.start >= 0,
              chunk.sampleRate.isFinite, (1000...384000).contains(chunk.sampleRate) else { return nil }
        if pending[chunk.source] == nil, chunk.start < (next[chunk.source] ?? 0) { return nil }
        var value = pending.removeValue(forKey: chunk.source) ?? Pending(start: chunk.start, expected: chunk.start)
        if abs(value.expected - chunk.start) > 0.12 { value = Pending(start: chunk.start, expected: chunk.start) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = try value.converter.buffer(chunk, format: format)
        if let samples = buffer.floatChannelData?[0] {
            let remaining = max(0, 48000 - value.samples.count)
            value.samples.append(contentsOf: UnsafeBufferPointer(start: samples, count: min(remaining, Int(buffer.frameLength))))
        }
        value.expected = chunk.start + Double(chunk.samples.count) / chunk.sampleRate
        guard value.samples.count >= 48000 else { pending[chunk.source] = value; return nil }
        next[chunk.source] = value.start + interval
        return LiveVocalWindow(source: chunk.source, start: value.start, samples: value.samples)
    }
}

enum LiveVocalAnalysis {
    struct Prediction: Sendable {
        let result: LiveVocalResult
        let embedding: [Float]?
    }

    @concurrent
    static func evaluate(_ window: LiveVocalWindow, session: UUID, settings: AppSettings,
                         allowModels: Bool, packageDirectory: URL? = nil) async throws -> Prediction {
        try Task.checkCancellation()
        let metrics = measure(window.samples)
        let choice = settings.vocalEmotionModel ?? .base
        let useEmotion = settings.vocalEmotionEnabled == true && (packageDirectory != nil || choice.package.installed)
        let identifiers = Set(settings.vocalSoundLabels ?? Array(VocalSoundAnalysis.defaultIdentifiers))
        let sampledEnd = window.start + Double(window.samples.count) / 16000
        let inference: Inferred?
        if allowModels, metrics.level >= -42 {
            inference = try await InferenceGate.shared.performIfIdle {
                try await infer(window, choice: useEmotion ? choice : nil,
                                embeddings: settings.vocalEmbeddingsEnabled == true, identifiers: identifiers,
                                directory: packageDirectory)
            }
        } else { inference = nil }
        let deferred = metrics.level >= -42 && (!allowModels || inference == nil)
        let result = LiveVocalResult(sessionID: session, source: window.source, start: window.start, end: sampledEnd,
            level: metrics.level, pitch: metrics.pitch, quietPercent: metrics.quietPercent,
            model: useEmotion ? choice : nil, modelIdentifier: useEmotion ? choice.identifier : nil,
            emotion: inference?.emotion, score: inference?.score, sounds: inference?.sounds ?? [], deferred: deferred)
        return Prediction(result: result, embedding: inference?.embedding)
    }

    private struct Inferred: Sendable {
        var emotion: VocalEmotion?
        var score: Double?
        var embedding: [Float]?
        var sounds: [LiveVocalSound] = []
    }

    @concurrent
    private static func infer(_ window: LiveVocalWindow, choice: VocalEmotionModel?, embeddings: Bool,
                              identifiers: Set<String>, directory: URL?) async throws -> Inferred {
        var result = Inferred()
        if let choice {
            // Loaded only for this optional sample, then released before sound analysis.
            result = try autoreleasepool {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuOnly
                let model = try MLModel(contentsOf: (directory ?? choice.package.directory).appendingPathComponent(choice.folder),
                                        configuration: configuration)
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                let pcm = try PCMConverter.buffer(AudioChunk(samples: window.samples, sampleRate: 16000,
                    start: window.start, source: window.source), format: format)
                let prediction = try VocalEmotionAnalysis.classify(pcm, model: model, choice: choice,
                    embeddings: embeddings && choice.embeddingDimension != nil)
                return Inferred(emotion: prediction.0?.emotion, score: prediction.0?.confidence, embedding: prediction.1)
            }
        }
        try Task.checkCancellation()
        if !identifiers.isEmpty { result.sounds = try await LiveSoundWindow(window: window, identifiers: identifiers).run() }
        return result
    }

    static func measure(_ samples: [Float]) -> (level: Double, pitch: Double?, quietPercent: Double) {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else { return (-120, nil, 100) }
        let rms = Double(vDSP.rootMeanSquare(samples))
        let level = max(-120, 20 * log10(max(1e-6, rms)))
        var quiet = 0, frames = 0
        for index in stride(from: 0, to: samples.count, by: 320) {
            let end = min(samples.count, index + 320)
            if vDSP.rootMeanSquare(Array(samples[index..<end])) < 0.005 { quiet += end - index }
            frames += end - index
        }
        var pitch: Double?
        if rms >= 0.008, samples.count >= 640 {
            let offset = (samples.count - 640) / 2
            var frame = Array(samples[offset..<(offset + 640)])
            let mean = vDSP.mean(frame)
            for index in frame.indices { frame[index] -= mean }
            var best: Float = 0, bestLag = 0
            var correlations=[Float](repeating:0,count:267)
            frame.withUnsafeBufferPointer { values in
                for lag in 32...266 {
                    var dot: Float = 0, a: Float = 0, b: Float = 0
                    let count = vDSP_Length(frame.count - lag)
                    vDSP_dotpr(values.baseAddress!, 1, values.baseAddress! + lag, 1, &dot, count)
                    vDSP_dotpr(values.baseAddress!, 1, values.baseAddress!, 1, &a, count)
                    vDSP_dotpr(values.baseAddress! + lag, 1, values.baseAddress! + lag, 1, &b, count)
                    let correlation = dot / sqrt(max(1e-12, a * b))
                    correlations[lag]=correlation
                    if correlation > best { best = correlation; bestLag = lag }
                }
            }
            if best >= 0.65 {
                if let first=(33...265).first(where: {
                    correlations[$0]>=best*0.97 && correlations[$0]>=correlations[$0-1] && correlations[$0]>=correlations[$0+1]
                }) { bestLag=first }
                if bestLag>0 { pitch=16000/Double(bestLag) }
            }
        }
        return (level, pitch, frames > 0 ? 100 * Double(quiet) / Double(frames) : 100)
    }
}

/// All SNAudioStreamAnalyzer calls run on one utility queue; only the result
/// accumulator crosses Apple's callback queue, protected by Mutex.
private final class LiveSoundWindow: NSObject, SNResultsObserving, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<[LiveVocalSound], any Error>?
        var results: [LiveVocalSound] = []
        var finished = false
    }
    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "paimon.live.sound", qos: .utility)
    private var analyzer: SNAudioStreamAnalyzer?
    private let window: LiveVocalWindow
    private let identifiers: Set<String>

    init(window: LiveVocalWindow, identifiers: Set<String>) { self.window = window; self.identifiers = identifiers }

    func run() async throws -> [LiveVocalSound] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = state.withLock { value in
                    if value.finished { return true }
                    value.continuation = continuation
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()); return }
                queue.async { [self] in
                    do {
                        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                        guard !identifiers.intersection(request.knownClassifications).isEmpty else { finish(.success([])); return }
                        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 1000)
                        request.overlapFactor = 0.5
                        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                        let input = try PCMConverter.buffer(.init(samples: window.samples, sampleRate: 16000,
                            start: window.start, source: window.source), format: format)
                        let analyzer = SNAudioStreamAnalyzer(format: format)
                        self.analyzer = analyzer
                        try analyzer.add(request, withObserver: self)
                        analyzer.analyze(input, atAudioFramePosition: 0)
                        analyzer.completeAnalysis()
                    } catch { finish(.failure(error)) }
                }
            }
        } onCancel: { [self] in
            finish(.failure(CancellationError()))
            queue.async { [self] in analyzer?.removeAllRequests(); analyzer = nil }
        }
    }

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = window.start + result.timeRange.start.seconds
        let end = min(window.start + 3, window.start + result.timeRange.end.seconds)
        guard start.isFinite, end.isFinite, end > start else { return }
        state.withLock { value in
            guard !value.finished else { return }
            for label in result.classifications where identifiers.contains(label.identifier) && label.confidence >= 0.65 {
                if value.results.count < 24 { value.results.append(.init(identifier: label.identifier, start: start, end: end)) }
            }
        }
    }
    func request(_ request: any SNRequest, didFailWithError error: any Error) { finish(.failure(error)) }
    func requestDidComplete(_ request: any SNRequest) {
        let values=state.withLock { $0.results }.sorted { $0.start<$1.start }
        var merged:[LiveVocalSound]=[]
        var last:[String:Int]=[:]
        for value in values {
            if let index=last[value.identifier],value.start<=merged[index].end+0.01 {
                let old=merged[index]
                merged[index]=LiveVocalSound(identifier:value.identifier,start:old.start,end:max(old.end,value.end))
            } else { last[value.identifier]=merged.count; merged.append(value) }
        }
        finish(.success(merged))
    }
    private func finish(_ result: Result<[LiveVocalSound], any Error>) {
        let continuation = state.withLock { value in
            guard !value.finished else { return Optional<CheckedContinuation<[LiveVocalSound], any Error>>.none }
            value.finished = true
            defer { value.continuation = nil }
            return value.continuation
        }
        if let continuation {
            continuation.resume(with: result)
            queue.async { [self] in analyzer?.removeAllRequests(); analyzer=nil }
        }
    }
}

actor LiveVocalSession {
    private let session: UUID
    private let settings: AppSettings
    private let store: SessionStore
    private let events: AsyncStream<PipelineEvent>.Continuation
    private let allowModels: Bool
    private var sampler: LiveVocalSampler
    private var suspended = false
    private var closed = false
    private var generation = 0
    private var previous: [AudioSource: (Double, [Float])] = [:]

    init(session: UUID, settings: AppSettings, store: SessionStore,
         events: AsyncStream<PipelineEvent>.Continuation, allowModels: Bool) {
        self.session = session; self.settings = settings; self.store = store; self.events = events
        self.allowModels = allowModels
        sampler = LiveVocalSampler(interval: settings.vocalLiveInterval ?? 30)
    }
    func suspend(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value; generation += 1; sampler.reset(); previous = [:]
    }
    func close() { closed = true; generation += 1; sampler.reset(); previous = [:] }

    func append(_ chunk: AudioChunk) async {
        guard !closed, !suspended, !Task.isCancelled else { return }
        do {
            guard let window = try sampler.append(chunk) else { return }
            let request = generation
            let prediction = try await LiveVocalAnalysis.evaluate(window, session: session,
                settings: settings, allowModels: allowModels)
            guard !closed, !suspended, !Task.isCancelled, request == generation else { return }
            var result = prediction.result
            if let vector = prediction.embedding {
                if let prior = previous[chunk.source], window.start - prior.0 <= sampler.interval * 1.5,
                   let similarity = VocalEmbeddingAnalysis.cosine(prior.1, vector) {
                    result.distanceFromPrevious = 1 - similarity
                }
                previous[chunk.source] = (window.start, vector)
            } else { previous[chunk.source] = nil }
            try await store.saveLiveVocal(result)
            events.yield(.liveVocal(result))
        } catch is CancellationError {
        } catch {
            events.yield(.vocalState(session, "Análisis vocal en vivo: " + error.localizedDescription))
        }
    }
}
