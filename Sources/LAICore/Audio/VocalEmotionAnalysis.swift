import Accelerate
import AVFoundation
import CoreML
import Foundation

public enum VocalEmotion: Int, CaseIterable, Sendable {
    case anger = 0, disgust, fear, joy, neutral
    case sadness = 6, surprise

    public var title: String {
        switch self {
        case .anger: "Enojo"
        case .disgust: "Disgusto"
        case .fear: "Miedo"
        case .joy: "Alegría"
        case .neutral: "Neutral"
        case .sadness: "Tristeza"
        case .surprise: "Sorpresa"
        }
    }
}

public struct VocalEmotionPoint: Identifiable, Sendable {
    public var id: Double { start }
    public let start: Double
    public let end: Double
    public let audioStart: Double
    public let audioEnd: Double
    public let emotion: VocalEmotion?
    public let confidence: Double?
    public var embedding: [Float]? = nil
}

public struct VocalEmotionReport: Sendable {
    public let points: [VocalEmotionPoint]
    public let sampled: Bool
    public var model: VocalEmotionModel = .base
    public var artifactIdentifier: String = VocalEmotionModel.base.identifier
}

public enum VocalEmotionAnalysis {
    private static let windowSeconds = 3.0
    private static let limit = 120
    private static let rate = 16_000.0
    private static let quietRMS: Float = 0.008 // About −42 dBFS.

    @concurrent
    public static func analyze(
        track: VocalAudioTrack, sessionDuration: Double,
        choice: VocalEmotionModel = .base, embeddings: Bool = false,
        packageDirectory: URL? = nil,
        progress: @Sendable (Double) async -> Void = { _ in }
    ) async throws -> VocalEmotionReport {
        try await InferenceGate.shared.perform {
            try await process(track, sessionDuration: sessionDuration, choice: choice, embeddings: embeddings,
                              packageDirectory: packageDirectory ?? choice.package.directory, progress: progress)
        }
    }

    private static func process(_ track: VocalAudioTrack, sessionDuration: Double, choice: VocalEmotionModel,
                                embeddings: Bool, packageDirectory: URL, progress: @Sendable (Double) async -> Void) async throws -> VocalEmotionReport {
        let scoped = track.url.startAccessingSecurityScopedResource()
        defer { if scoped { track.url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: track.url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let inputRate = file.processingFormat.sampleRate
        let fileLength = file.length
        let fileDuration = Double(fileLength) / inputRate
        guard fileDuration.isFinite, fileDuration > 0, (1_000...384_000).contains(inputRate),
              let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(inputRate * windowSeconds)),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else {
            throw LAIError.message("El archivo de audio está vacío o no es compatible")
        }
        let duration = sessionDuration.isFinite && sessionDuration > 0
            ? (track.isArchived ? max(sessionDuration, fileDuration) : min(sessionDuration, fileDuration))
            : fileDuration
        let spacing = max(windowSeconds, ceil(duration / Double(limit)))
        let configuration = MLModelConfiguration()
        // On the M1 the CPU had a lower cold-start cost and footprint in the measured run.
        configuration.computeUnits = .cpuOnly
        let modelURL = packageDirectory.appendingPathComponent(choice.folder)
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["audio"]?.type == .multiArray,
              model.modelDescription.outputDescriptionsByName["probs"]?.multiArrayConstraint?.shape.last?.intValue == choice.classes.count else {
            throw LAIError.message("El modelo de emociones no tiene la interfaz esperada.")
        }
        let useEmbeddings = embeddings && choice.embeddingDimension != nil
        if useEmbeddings {
            guard model.modelDescription.outputDescriptionsByName["embedding"]?.multiArrayConstraint?.shape.last?.intValue == choice.embeddingDimension else {
                throw LAIError.message("Este modelo no expone un embedding compatible.")
            }
        }
        var points: [VocalEmotionPoint] = []
        var nextTime = 0.0
        var sampled = spacing > windowSeconds
        try await track.forEachSpan(fileLength: fileLength, rate: inputRate, duration: duration) { span in
            let spanEnd = min(duration, span.start + Double(span.count) / inputRate)
            while spanEnd - max(nextTime, span.start) >= 0.5 {
                try Task.checkCancellation()
                guard points.count < limit else { sampled = true; break }
                let offset = Int64(((max(nextTime, span.start) - span.start) * inputRate).rounded(.up))
                let start = span.start + Double(offset) / inputRate
                let count = min(span.count - offset, Int64(((spanEnd - start) * inputRate).rounded(.down)), Int64(pcm.frameCapacity))
                guard count >= Int64(ceil(0.5 * inputRate)) else { break }
                file.framePosition = span.frame + offset
                try file.read(into: pcm, frameCount: AVAudioFrameCount(count))
                let frames = Int(pcm.frameLength)
                guard frames >= Int(ceil(0.5 * inputRate)), let channels = pcm.floatChannelData else { break }

                var samples = [Float](repeating: 0, count: frames)
                let channelCount = Int(pcm.format.channelCount)
                for i in samples.indices {
                    var sum: Float = 0
                    for channel in 0..<channelCount { sum += channels[channel][i] }
                    samples[i] = sum.isFinite ? max(-1, min(1, sum / Float(channelCount))) : 0
                }
                let end = start + Double(frames) / inputRate
                let audioStart = Double(span.frame + offset) / inputRate
                var classification: (emotion: VocalEmotion, confidence: Double)?
                var embedding: [Float]?
                if vDSP.rootMeanSquare(samples) >= quietRMS {
                    let chunk = AudioChunk(samples: samples, sampleRate: inputRate, start: start, source: track.source)
                    let converted = try PCMConverter.buffer(chunk, format: outputFormat)
                    let result = try autoreleasepool { try classify(converted, model: model, choice: choice, embeddings: useEmbeddings) }
                    classification = result.0
                    embedding = result.1
                }
                points.append(VocalEmotionPoint(start: start, end: end, audioStart: audioStart,
                                                audioEnd: audioStart + end - start, emotion: classification?.emotion,
                                                confidence: classification?.confidence, embedding: embedding))
                nextTime = start + spacing
                await progress(min(1, end / duration))
            }
        }
        try Task.checkCancellation()
        await progress(1)
        return VocalEmotionReport(points: points, sampled: sampled, model: choice, artifactIdentifier: choice.identifier)
    }

    private static func classify(_ pcm: AVAudioPCMBuffer, model: MLModel, choice: VocalEmotionModel,
                                 embeddings: Bool) throws -> ((emotion: VocalEmotion, confidence: Double)?, [Float]?) {
        let count = Int(pcm.frameLength)
        guard count >= 8_000, let samples = pcm.floatChannelData?[0] else { return (nil, nil) }
        try Task.checkCancellation()
        let audio = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .float32)
        let values = audio.dataPointer.assumingMemoryBound(to: Float.self)
        for index in 0..<count { values[index] = max(-1, min(1, samples[index])) }
        let features = try MLDictionaryFeatureProvider(dictionary: ["audio": MLFeatureValue(multiArray: audio)])
        let prediction = try model.prediction(from: features)
        guard let probabilities = prediction.featureValue(for: "probs")?.multiArrayValue, probabilities.count == choice.classes.count else {
            throw LAIError.message("La salida del modelo de emociones no es compatible.")
        }
        let scores = (0..<probabilities.count).map { probabilities[$0].doubleValue }
        var vector: [Float]?
        if embeddings {
            guard let value = prediction.featureValue(for: "embedding")?.multiArrayValue,
                  value.count == choice.embeddingDimension else {
                throw LAIError.message("El modelo no devolvió un embedding válido.")
            }
            let values = (0..<value.count).map { value[$0].floatValue }
            guard values.allSatisfy(\.isFinite) else { throw LAIError.message("El embedding contiene valores no finitos.") }
            vector = values
        }
        return (estimate(scores, choice: choice), vector)
    }

    static func estimate(_ scores: [Double], choice: VocalEmotionModel = .base) -> (emotion: VocalEmotion, confidence: Double)? {
        guard scores.count == choice.classes.count, scores.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let ranked = scores.indices.sorted { scores[$0] > scores[$1] }
        guard let best = ranked.first, let emotion = choice.classes[best],
              scores[best] >= 0.65, scores[best] - scores[ranked[1]] >= 0.15 else { return nil }
        return (emotion, scores[best])
    }
}
