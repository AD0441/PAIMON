import Accelerate
import Foundation

public enum VocalEmotionModel: String, Codable, CaseIterable, Sendable {
    case base, large, superb

    public var title: String {
        switch self {
        case .base: "emotion2vec+ Base"
        case .large: "emotion2vec+ Large"
        case .superb: "Wav2Vec2 Base · SUPERB ER"
        }
    }
    public var detail: String {
        switch self {
        case .base: "Modelo actual de 94 MB. Nueve salidas; sin embeddings accesibles en esta conversión."
        case .large: "Modelo ampliado. Nueve salidas y representación vocal de 1024 componentes."
        case .superb: "Cuatro categorías: neutral, alegría, enojo y tristeza. Entrenado con audio en inglés; uso en español experimental."
        }
    }
    public var package: OptionalModelPackage {
        switch self {
        case .base: .vocalEmotion
        case .large: .vocalEmotionLarge
        case .superb: .vocalEmotionSuperb
        }
    }
    public var folder: String {
        switch self {
        case .base: "Emotion2Vec8bit.mlmodelc"
        case .large: "EmotionLarge.mlmodelc"
        case .superb: "Wav2VecSuperb.mlmodelc"
        }
    }
    public var identifier: String {
        switch self {
        case .base: "emotion2vec-base-704a2cac-int8"
        case .large: "emotion2vec-large-6c303ba9-coreml-v1"
        case .superb: "wav2vec-superb-441a7599-coreml-v1"
        }
    }
    public var embeddingDimension: Int? {
        switch self { case .base: nil; case .large: 1024; case .superb: 256 }
    }
    public var classes: [VocalEmotion?] {
        self == .superb ? [.neutral, .joy, .anger, .sadness]
            : [.anger, .disgust, .fear, .joy, .neutral, nil, .sadness, .surprise, nil]
    }
}

public enum VocalEmbeddingAnalysis {
    public struct Similarity: Identifiable, Sendable {
        public let id: Double
        public let end: Double
        public let value: Double
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Double? {
        guard !a.isEmpty, a.count == b.count, a.count <= 4096,
              a.allSatisfy(\.isFinite), b.allSatisfy(\.isFinite) else { return nil }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        guard normA > 1e-12, normB > 1e-12 else { return nil }
        let value = Double(dot) / sqrt(Double(normA) * Double(normB))
        return value.isFinite ? max(-1, min(1, value)) : nil
    }

    @concurrent
    public static func similar(to point: VocalEmotionPoint, in report: VocalEmotionReport) async throws -> [Similarity] {
        guard let reference = point.embedding else { return [] }
        var result: [Similarity] = []
        for other in report.points where other.id != point.id {
            try Task.checkCancellation()
            guard let embedding = other.embedding, let value = cosine(reference, embedding) else { continue }
            result.append(.init(id: other.start, end: other.end, value: value))
        }
        return Array(result.sorted { $0.value > $1.value }.prefix(5))
    }
}

extension VocalEmbeddingAnalysis {
    public struct Change: Identifiable, Sendable {
        public var id: Double { start }
        public let start: Double
        public let distance: Double
        public let speakerChanged: Bool?
    }

    @concurrent
    public static func changes(in report: VocalEmotionReport, threshold: Double,
                               speakers: [Double: String] = [:]) async throws -> [Change] {
        let threshold = threshold.isFinite ? min(1, max(0.05, threshold)) : 0.2
        var result: [Change] = []
        // Never bridge silent or unmeasurable windows by removing them first.
        for (before, after) in zip(report.points, report.points.dropFirst()) {
            try Task.checkCancellation()
            guard let a = before.embedding, let b = after.embedding, let similarity = cosine(a, b) else { continue }
            let distance = 1 - similarity
            guard distance >= threshold else { continue }
            let changed: Bool?
            if let a = speakers[before.start], let b = speakers[after.start] { changed = a != b }
            else { changed = nil }
            result.append(.init(start: after.start, distance: distance, speakerChanged: changed))
        }
        return Array(result.sorted { $0.distance > $1.distance }.prefix(12))
    }
}
