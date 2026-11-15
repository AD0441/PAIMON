import Foundation
import FoundationModels
import NaturalLanguage

public struct SentimentPoint: Codable, Sendable, Identifiable {
    public let id: Int
    public let segmentID: String
    public let time: Double?
    public let excerpt: String
    public let speaker: String?
    public let speakerNumber: Int?
    public var score: Double?
    public var rawAppleScore: Double? = nil
    public var polarity: TextSentimentClass? = nil
    public var strength: SentimentStrength? = nil
    public var polarityEvidence: String? = nil
    public var emotions: [String] = []
    public var context: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, segmentID, time, excerpt, speaker, speakerNumber, score, rawAppleScore
        case polarity, strength, polarityEvidence, emotions, context
    }
    public func encode(to encoder: any Encoder) throws {
        var value=encoder.container(keyedBy:CodingKeys.self)
        try value.encode(id,forKey:.id); try value.encode(segmentID,forKey:.segmentID)
        try value.encode(time,forKey:.time); try value.encode(excerpt,forKey:.excerpt)
        try value.encodeIfPresent(speaker,forKey:.speaker); try value.encodeIfPresent(speakerNumber,forKey:.speakerNumber)
        // A missing measurement is explicit null, never a default zero or −1.
        try value.encode(score,forKey:.score); try value.encode(rawAppleScore,forKey:.rawAppleScore)
        try value.encodeIfPresent(polarity,forKey:.polarity); try value.encodeIfPresent(strength,forKey:.strength)
        try value.encodeIfPresent(polarityEvidence,forKey:.polarityEvidence)
        try value.encode(emotions,forKey:.emotions); try value.encode(context,forKey:.context)
    }
}

public struct TranscriptSentiment: Codable, Sendable {
    public enum Tagging: String, Codable, Sendable {
        case complete, unavailable, unsupported, partial
    }

    static let version = 2
    public static let changeThreshold = 0.55
    public let points: [SentimentPoint]
    public let tagging: Tagging
    public let tagged: Int

    public var usesTime: Bool { !points.isEmpty && points.allSatisfy { $0.time != nil } }
    public var boundaryConcentration: (score: Double, count: Int, total: Int)? {
        let scores = points.compactMap(\.score)
        guard scores.count >= 5 else { return nil }
        for boundary in [-1.0, 1.0] {
            let count = scores.count { $0 == boundary }
            if count > scores.count / 2 { return (boundary, count, scores.count) }
        }
        return nil
    }

    public var emotionCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for point in points {
            for emotion in Set(point.emotions) { counts[emotion, default: 0] += 1 }
        }
        return counts.map { ($0.key, $0.value) }.sorted {
            $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1
        }
    }

    public struct Moment: Identifiable, Sendable {
        public enum Reason: Sendable { case positive, negative, change, topicChange, emotion }
        public let point: SentimentPoint
        public let reason: Reason
        public let previousScore: Double?
        public var id: Int { point.id }
    }

    public func moments(limit: Int = 8) -> [Moment] {
        var previous: SentimentPoint?
        var candidates: [(priority: Double, moment: Moment)] = []
        for point in points {
            defer { previous = point }
            let change = previous?.score.flatMap { old in point.score.map { abs($0 - old) } } ?? 0
            let linked = previous.map { !Set($0.context).isDisjoint(with: point.context) } ?? false
            let reason: Moment.Reason
            let priority: Double
            if change >= Self.changeThreshold {
                reason = linked ? .topicChange : .change
                priority = 2 + change
            } else if let score = point.score, abs(score) >= 0.55 {
                reason = score > 0 ? .positive : .negative
                priority = 1 + abs(score)
            } else if !point.emotions.isEmpty {
                reason = .emotion
                priority = 0.5
            } else { continue }
            let previousScore = change >= Self.changeThreshold ? previous?.score : nil
            candidates.append((priority, Moment(point: point, reason: reason, previousScore: previousScore)))
        }
        return candidates.sorted {
            $0.priority == $1.priority ? $0.moment.id < $1.moment.id : $0.priority > $1.priority
        }.prefix(limit).map(\.moment).sorted { $0.id < $1.id }
    }

    // Keep local inference bounded for long sessions. Include pronounced changes
    // and distribute the remaining samples across the full transcript.
    func tagTargets() -> [Int] {
        let limit = 48
        guard points.count > limit else { return Array(points.indices) }
        var targets = Set(moments(limit: limit / 3).map(\.id))
        targets.formUnion([0, points.count - 1])
        let slots = limit - targets.count
        for slot in 0..<slots {
            targets.insert((slot + 1) * (points.count - 1) / (slots + 1))
        }
        return targets.sorted()
    }
}

enum TextPolarity {
    static func language(of text: String, fallback: Locale) -> NLLanguage? {
        if let detected = NLLanguageRecognizer.dominantLanguage(for: text), detected != .undetermined { return detected }
        return fallback.language.languageCode.map { NLLanguage(rawValue: $0.identifier) }
    }

    static func score(_ text: String, language: NLLanguage?) -> Double? {
        NativePolarityScorer().score(text, language: language)
    }
}

/// One instance per serial analysis task, never shared between tasks.
final class NativePolarityScorer {
    private let tagger = NLTagger(tagSchemes: [.sentimentScore])
    private var supported: [NLLanguage: Bool] = [:]
    func score(_ text: String, language: NLLanguage?) -> Double? {
        autoreleasepool {
            guard let language, !text.isEmpty else { return nil }
            let available = supported[language] ?? NLTagger.availableTagSchemes(for: .paragraph, language: language).contains(.sentimentScore)
            supported[language] = available
            guard available else { return nil }
            tagger.string = text
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
            let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            guard let raw = tag?.rawValue, let value = Double(raw), value.isFinite, (-1...1).contains(value) else { return nil }
            return value
        }
    }
}

protocol SentimentTagging: Sendable {
    var isAvailable: Bool { get }
    func supportsLocale(_ locale: Locale) -> Bool
    func assess(_ texts: [String], locale: Locale) async throws -> [SentimentAssessment?]
}

public enum SentimentAnalyzer {
    // Analyze the original chronological fragments. Split exceptional long edits
    // at sentences or whitespace. All pieces retain the original segment time.
    static func excerpts(_ text: String) -> [String] {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty else { return [] }
        let limit = 650
        guard clean.count > limit else { return [clean] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = clean
        var result: [String] = []
        var pending = ""
        for range in tokenizer.tokens(for: clean.startIndex..<clean.endIndex) {
            var sentence = String(clean[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !pending.isEmpty && pending.count + 1 + sentence.count > limit {
                result.append(pending)
                pending = ""
            }
            while sentence.count > limit {
                let prefix = sentence.prefix(limit)
                let boundary = prefix.lastIndex(of: " ") ?? prefix.endIndex
                result.append(String(sentence[..<boundary]))
                sentence = String(sentence[boundary...]).trimmingCharacters(in: .whitespaces)
            }
            if !sentence.isEmpty { pending += pending.isEmpty ? sentence : " " + sentence }
        }
        if !pending.isEmpty { result.append(pending) }
        return result
    }

    @concurrent
    public static func analyze(
        session: Session, store: SessionStore,
        progress: @Sendable (Double) async -> Void = { _ in }
    ) async throws -> TranscriptSentiment {
        try await analyze(session: session, store: store, tagger: LocalSentimentClassifier(), progress: progress)
    }

    @concurrent
    static func analyze(
        session: Session, store: SessionStore, tagger: any SentimentTagging,
        progress: @Sendable (Double) async -> Void = { _ in }
    ) async throws -> TranscriptSentiment {
        let stamp = try await store.sentimentStamp(session: session.id)
        let locale = Locale(identifier: session.settings.locale)
        var cursor: Int64 = 0
        var processed = 0
        var points: [SentimentPoint] = []
        do {
            let rawScorer = NativePolarityScorer()
            while cursor < stamp.lastRow {
                try Task.checkCancellation()
                let rows = try await store.segments(session: session.id, after: cursor, limit: 120, before: stamp.lastRow + 1)
                guard let last = rows.last else { break }
                cursor = last.0
                let segments = rows.map(\.1).filter { $0.isFinal && $0.duplicateOf == nil }
                let speakers = session.settings.diarizationEnabled == true
                    ? try await store.speakers(for: segments, session: session.id) : [:]
                for segment in segments {
                    let speaker = speakers[segment.id]
                    let time = segment.start.isFinite && segment.start >= 0 && segment.end.isFinite && segment.end > segment.start && segment.end < Double(Int.max)
                        ? segment.start : nil
                    for excerpt in excerpts(segment.text) {
                        try Task.checkCancellation()
                        let language = TextPolarity.language(of: excerpt, fallback: locale)
                        points.append(SentimentPoint(id: points.count, segmentID: segment.id, time: time,
                                                     excerpt: excerpt, speaker: speaker?.name, speakerNumber: speaker?.number,
                                                     score: nil, rawAppleScore: rawScorer.score(excerpt, language: language)))
                    }
                }
                processed += rows.count
                await progress(0.5 * Double(processed) / Double(max(1, stamp.rows)))
            }
        }
        if points.allSatisfy({ $0.time != nil }) {
            points.sort { ($0.time ?? 0, $0.id) < ($1.time ?? 0, $1.id) }
            points = points.enumerated().map { index, point in
                SentimentPoint(id: index, segmentID: point.segmentID, time: point.time, excerpt: point.excerpt,
                               speaker: point.speaker, speakerNumber: point.speakerNumber, score: point.score, rawAppleScore: point.rawAppleScore)
            }
        }

        var status: TranscriptSentiment.Tagging = tagger.isAvailable ? .complete : .unavailable
        var tagged = 0
        if status == .complete, !tagger.supportsLocale(locale) { status = .unsupported }
        if status == .complete {
            let targets = TranscriptSentiment(points: points, tagging: status, tagged: 0).tagTargets()
            var failed = 0
            var consecutiveFailures = 0
            var offset = 0
            while offset < targets.count {
                try Task.checkCancellation()
                var batch: [Int] = []
                var characters = 0
                while offset + batch.count < targets.count, batch.count < 3 {
                    let index = targets[offset + batch.count]
                    let length = points[index].excerpt.count
                    if !batch.isEmpty, characters + length > 1800 { break }
                    batch.append(index); characters += length
                }
                let taggedBefore = tagged
                do {
                    let output = try await tagger.assess(batch.map { points[$0].excerpt }, locale: locale)
                    for (position, index) in batch.enumerated() {
                        guard position < output.count, let value = output[position] else { failed += 1; continue }
                        points[index].score = value.score
                        points[index].polarity = value.polarity
                        points[index].strength = [.positive,.negative].contains(value.polarity) ? value.strength:nil
                        points[index].polarityEvidence = value.quote
                        points[index].emotions = value.emotions
                        points[index].context = value.context
                        tagged += 1
                    }
                } catch {
                    try Task.checkCancellation()
                    failed += batch.count
                }
                consecutiveFailures = tagged == taggedBefore ? consecutiveFailures + 1 : 0
                offset += batch.count
                await progress(0.5 + 0.5 * Double(offset) / Double(targets.count))
                if !tagger.isAvailable { status = .unavailable; break }
                if consecutiveFailures >= 3 { break }
            }
            if status == .complete, failed > 0 { status = .partial }
        }

        try Task.checkCancellation()
        let result = TranscriptSentiment(points: points, tagging: status, tagged: tagged)
        try await store.saveSentiment(result, session: session.id, stamp: stamp)
        return result
    }
}
