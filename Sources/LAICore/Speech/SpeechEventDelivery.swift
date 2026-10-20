import Foundation

/// Used only with the persistence stream's bufferingOldest policy. Partial
/// hypotheses may be coalesced; finalized text must be accepted or fail visibly.
public enum SpeechEventDelivery {
    public static func emit(_ segment:TranscriptSegment,to events:AsyncStream<PipelineEvent>.Continuation,timeout:Duration = .seconds(3)) async throws {
        if !segment.isFinal { events.yield(.segment(segment)); return }
        let started=ContinuousClock.now
        while true {
            try Task.checkCancellation()
            switch events.yield(.segment(segment)) {
            case .enqueued: return
            case .terminated: throw CancellationError()
            case .dropped:
                guard started.duration(to:.now) < timeout else { throw LAIError.message("La cola de texto definitivo no pudo guardarse. Se detuvo el reconocimiento para evitar pérdidas silenciosas.") }
                try await Task.sleep(for:.milliseconds(20))
            @unknown default: throw LAIError.message("No se pudo entregar el texto definitivo")
            }
        }
    }
}
