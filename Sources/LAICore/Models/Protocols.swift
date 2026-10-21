import Foundation
public struct AudioChunk: Sendable {
    public var samples: [Float]
    public var sampleRate: Double
    public var start: Double
    public var source: AudioSource
    public init(samples: [Float], sampleRate: Double, start: Double, source: AudioSource) { self.samples=samples; self.sampleRate=sampleRate; self.start=start; self.source=source }
}
public enum PipelineEvent: Sendable {
    case segment(TranscriptSegment), activity(AudioSource, Float, Bool), warning(String), failure(String)
}
public protocol TranscriptionEngine: Actor {
    func start(sessionID: UUID, sources: [AudioSource], settings: AppSettings, events: AsyncStream<PipelineEvent>.Continuation) async throws
    func append(_ chunk: AudioChunk) async throws
    func finish() async throws
    func cancel() async
}
public protocol SummarizationEngine: Actor {
    func identifier() async -> String?
    func processingVersion() async -> Int
    func availability(locale: String) async -> String?
    func summarize(segments: [TranscriptSegment], previous: [Finding], final: Bool, locale: String) async throws -> [Finding]
    func unload() async
}
public extension SummarizationEngine {
    func processingVersion() -> Int { 1 }
    func identifier() -> String? { nil }
}
public struct VAD: Sendable {
    public private(set) var active = false
    private var quiet: Double = 0
    public init() {}
    public mutating func process(_ samples: [Float], sampleRate: Double) -> (Float, Bool) {
        guard !samples.isEmpty else { return (0,false) }
        let rms=sqrt(samples.reduce(Float(0)) { $0+$1*$1 }/Float(samples.count))
        if rms > 0.012 { active=true; quiet=0 } else { quiet += Double(samples.count)/sampleRate; if quiet>0.65 { active=false } }
        return (rms,active)
    }
}
