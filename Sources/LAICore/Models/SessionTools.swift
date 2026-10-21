import Foundation

public enum SummaryTemplate:String,Codable,Sendable,CaseIterable,Identifiable {
    case meeting, lecture, video
    public var id:Self { self }
    public var title:String {
        switch self { case .meeting:"Reunión"; case .lecture:"Clase"; case .video:"Video o podcast" }
    }
    public var instructions:String {
        switch self {
        case .meeting: "Prioriza acuerdos explícitos, decisiones, tareas y preguntas pendientes. No deduzcas compromisos."
        case .lecture: "Prioriza conceptos, definiciones, explicaciones, ejemplos y preguntas. No conviertas explicaciones en tareas o acuerdos."
        case .video: "Prioriza el tema, la tesis, los argumentos y las conclusiones. No atribuyas al oyente compromisos expresados por otras personas."
        }
    }
}
public struct SessionBookmark:Identifiable,Codable,Sendable,Hashable {
    public var id:UUID
    public var sessionID:UUID
    public var time:Double
    public var note:String
    public var segmentID:String?
    public var created:Date
    public init(sessionID:UUID,time:Double,note:String="",segmentID:String?=nil) {
        id=UUID(); self.sessionID=sessionID; self.time=max(0,time.isFinite ? time:0)
        self.note=String(note.prefix(2000)); self.segmentID=segmentID; created=Date()
    }
}
public struct TranscriptSearchHit:Identifiable,Sendable {
    public var id:Int64
    public var sessionID:UUID
    public var title:String
    public var created:Date
    public var segmentID:String
    public var source:AudioSource
    public var start:Double
    public var snippet:String
}
