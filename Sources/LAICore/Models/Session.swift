import Foundation
public enum AudioSource: String, Codable, Sendable, CaseIterable { case system, microphone, file
    public var title: String { switch self { case .system: "Sistema"; case .microphone: "Micrófono"; case .file: "Archivo" } }
}
public enum CaptureState: String, Sendable { case idle, preparing, recording, paused, stopping, importing, failed }
public enum AppPalette:String,Codable,CaseIterable,Sendable,Identifiable {
    case petroleum,sage,copper,graphite
    public var id:String { rawValue }
    public var title:String { switch self { case .petroleum:"Petróleo"; case .sage:"Salvia"; case .copper:"Cobre"; case .graphite:"Grafito" } }
}
public enum AppLanguage:String,Codable,CaseIterable,Sendable,Identifiable {
    case spanish="es",english="en"
    public var id:String { rawValue }
    public var title:String { switch self { case .spanish:"Español"; case .english:"English" } }
    public var locale:Locale { Locale(identifier:rawValue) }
}
public enum TranscriptionBackend: String, Codable, CaseIterable, Sendable { case automatic, apple, fluid }
public enum SummaryBackend: String, Codable, CaseIterable, Sendable { case apple, mlx, google
    public var title:String { switch self { case .apple:"Apple · local"; case .mlx:"MLX · local"; case .google:"Google AI · externo" } }
}
public struct AppSettings: Codable, Sendable {
    public var transcription: TranscriptionBackend = .automatic
    public var summary: SummaryBackend = .apple
    public var locale = "es-ES"
    public var summaryInterval: Double = 300
    public var summaryTemplate:SummaryTemplate?
    public var colorPalette:AppPalette?
    public var interfaceLanguage:AppLanguage?
    public var googleEnabled:Bool?
    public var googleModel:String?
    public var googleSummarySelected:Bool?
    public var microphone = false
    public var microphoneDevice: UInt32 = 0
    public var systemAudio = true
    public var applicationBundleID = ""
    public var outputDeviceUID = ""
    public var saveAudio = false
    public var energySaving = true
    public var fluidWorker = ""
    public var fluidModels = ""
    public var mlxPython = ""
    public var mlxScript = ""
    public var mlxModel = ""
    public init() {}
    public func forNewSession() -> Self {
        var value=self
        value.googleSummarySelected=googleEnabled==true
        // Keep the original local raw value readable by the previous app.
        value.summary=summary == .mlx ? .mlx:.apple
        return value
    }
    public func summaryBackend(googleAllowed:Bool) -> SummaryBackend {
        if googleSummarySelected==true && googleAllowed { return .google }
        return summary == .mlx ? .mlx:.apple
    }
    public static func load(from defaults:UserDefaults = .standard) -> Self {
        // Recover preferences if an explicit DEBUG audio validation was killed.
        // The backup contains settings only, never audio or transcript content.
        if let data=defaults.data(forKey:"audioValidationSettingsBackup"),let value=try? JSONDecoder().decode(Self.self,from:data) {
            defaults.set(data,forKey:"settings")
            defaults.removeObject(forKey:"audioValidationSettingsBackup")
            return value
        }
        guard let data = defaults.data(forKey: "settings"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }; return value
    }
    public func save(to defaults:UserDefaults = .standard) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "settings") } }
}
public struct Session: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var title: String
    public var created: Date
    public var duration: Double
    public var status: String
    public var settings: AppSettings
    public var summaryTemplate:SummaryTemplate?
    public var context:SessionContext?
    public var importedFileName:String?
    public var template:SummaryTemplate { summaryTemplate ?? .meeting }
    public init(title: String, settings: AppSettings) { id=UUID(); self.title=title; created=Date(); duration=0; status="recording"; self.settings=settings; summaryTemplate=settings.summaryTemplate }
    public static func ==(l: Self, r: Self) -> Bool { l.id == r.id && l.title == r.title && l.duration == r.duration && l.status == r.status && l.template == r.template }
    public func hash(into h: inout Hasher) { h.combine(id) }
}
public struct TranscriptSegment: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var sessionID: UUID
    public var source: AudioSource
    public var start: Double
    public var end: Double
    public var text: String
    public var isFinal: Bool
    public var duplicateOf: String?
    public init(sessionID: UUID, source: AudioSource, start: Double, end: Double, text: String, isFinal: Bool = true) {
        id="\(source.rawValue)-\(Int((start*1000).rounded()))"; self.sessionID=sessionID; self.source=source
        self.start=start; self.end=end; self.text=text; self.isFinal=isFinal
    }
}
public enum FindingKind: String, CaseIterable, Codable, Sendable {
    case topic, overview, idea, decision, task, concept, question, conclusion
    public var title: String { switch self { case .topic: "Tema de la reunión"; case .overview: "Resumen general"; case .idea: "Ideas principales"; case .decision: "Acuerdos y decisiones"; case .task: "Tareas pendientes"; case .concept: "Conceptos relevantes"; case .question: "Preguntas abiertas"; case .conclusion: "Conclusiones" } }
}
public struct FindingEvidence:Codable,Sendable,Hashable {
    public var segmentID:String
    public var quote:String
    public var start:Double
    public var end:Double
    public init(segmentID:String,quote:String,start:Double,end:Double) { self.segmentID=segmentID; self.quote=quote; self.start=start; self.end=end }
    public var sourceTitle:String { AudioSource.allCases.first{segmentID.hasPrefix($0.rawValue+"-")}?.title ?? "Fuente local" }
}
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID = UUID()
    public var kind: FindingKind
    public var text: String
    public var segmentID: String
    public var quote: String
    public var start: Double
    public var end: Double
    public var owner: String?
    public var due: String?
    public var additionalEvidence:[FindingEvidence]?
    public var evidence:[FindingEvidence] { [.init(segmentID:segmentID,quote:quote,start:start,end:end)]+(additionalEvidence ?? []) }
    public init(kind: FindingKind, text: String, segmentID: String, quote: String, start: Double, end: Double, owner: String? = nil, due: String? = nil,additionalEvidence:[FindingEvidence]=[]) {
        self.kind=kind; self.text=text; self.segmentID=segmentID; self.quote=quote; self.start=start; self.end=end; self.owner=owner; self.due=due
        self.additionalEvidence=additionalEvidence.isEmpty ? nil:additionalEvidence
    }
}
public struct SummarySnapshot: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var sessionID: UUID
    public var created = Date()
    public var throughRow: Int64
    public var isFinal: Bool
    public var duplicateOf: String?
    public var findings: [Finding]
    public var summaryTemplate:SummaryTemplate?
    public var processingVersion:Int?
    public var engineIdentifier:String?
    public init(sessionID: UUID, throughRow: Int64, isFinal: Bool, findings: [Finding],template:SummaryTemplate?=nil,processingVersion:Int=1) { self.sessionID=sessionID; self.throughRow=throughRow; self.isFinal=isFinal; self.findings=findings; summaryTemplate=template; self.processingVersion=processingVersion }
}
public enum LAIError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): text } }
}
public func timestamp(_ seconds: Double) -> String { let n=max(0,Int(seconds)); return String(format: "%02d:%02d:%02d", n/3600,(n/60)%60,n%60) }
