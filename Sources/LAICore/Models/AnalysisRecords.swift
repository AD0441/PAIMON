import Foundation

public struct AssistantTurn: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let created: Date
    public let transcriptRevision: Int64
    public let question: String
    public let reply: TranscriptAssistantReply
    public init(sessionID: UUID, revision: Int64, question: String, reply: TranscriptAssistantReply) {
        id = UUID(); self.sessionID = sessionID; created = Date()
        transcriptRevision = revision; self.question = question; self.reply = reply
    }
}

public struct SavedSentiment: Codable, Sendable {
    public let version: Int
    public let matchesCurrentTranscript: Bool
    public let report: TranscriptSentiment
    public let engine: String
    public init(version: Int, matchesCurrentTranscript: Bool, report: TranscriptSentiment) {
        self.version=version; self.matchesCurrentTranscript=matchesCurrentTranscript; self.report=report
        engine=version<2 ? "NaturalLanguage":"Apple Foundation Models"
    }
}

public struct VocalDistance: Codable, Sendable {
    public let from: Double
    public let to: Double
    public let distance: Double
}

public struct SavedVocalAnalysis: Codable, Sendable {
    public let source: AudioSource
    public var updated: Date
    public var measurements: [VocalPoint]?
    public var emotions: VocalEmotionReport?
    public var sounds: VocalSoundReport?
    public var soundIdentifiers: [String]?
    public var distances: [VocalDistance]?
}
