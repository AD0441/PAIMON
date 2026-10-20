import Foundation

public enum SummaryContextError:LocalizedError,Sendable {
    case exceeded
    public var errorDescription:String? { "El contexto del modelo sigue siendo insuficiente tras reducir el lote. La transcripción está guardada." }
}

public struct PendingSummaryContent:Sendable {
    public var segments:Int
    public var bytes:Int
    public init(segments:Int=0,bytes:Int=0) { self.segments=segments; self.bytes=bytes }
}

/// Pure policy: do no inference for silence; limit latency when speech is dense.
public enum SummarySchedule {
    public static func shouldUpdate(pending:PendingSummaryContent,secondsSinceUpdate:Double,interval:Double,underPressure:Bool) -> Bool {
        guard !underPressure,pending.segments>0 else { return false }
        return secondsSinceUpdate>=max(60,interval) || (secondsSinceUpdate>=60 && pending.bytes>=6000)
    }
}

public struct SummaryRunMetrics:Codable,Sendable {
    public var id=UUID()
    public var sessionID:UUID
    public var created=Date()
    public var seconds:Double
    public var cpuSeconds:Double
    public var clientFootprintMB:Double
    public var pendingSegments:Int
    public var processedBatches:Int
    public var contextReductions:Int
    public var throughRow:Int64
    public var final:Bool
    public var outcome:String
}
