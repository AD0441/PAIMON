import Foundation
import AVFoundation
// One Parakeet worker/model shared by both sources. Whole utterances, no overlapping
// windows: repetition at artificial overlap boundaries is avoided by construction.
public actor FluidSpeechEngine: TranscriptionEngine {
    struct Utterance {
        static let sampleRate = 16_000.0
        static let limit = 240_000
        var samples:[Float]=[]
        var start:Double=0
        var quiet:Double=0
        var speech=false

        mutating func takeFullWindow() -> Utterance? {
            guard speech,samples.count>=Self.limit else { return nil }
            let window=Utterance(samples:Array(samples.prefix(Self.limit)),start:start,speech:true)
            samples.removeFirst(Self.limit)
            start+=Double(Self.limit)/Self.sampleRate
            if samples.isEmpty { quiet=0; speech=false }
            return window
        }
    }
    private let worker=LocalWorker()
    private var converters:[AudioSource:PCMStreamConverter]=[:]
    private var utterances:[AudioSource:Utterance]=[:]
    private var executable=""
    private var modelPath=""
    private var sessionID=UUID()
    private var events:AsyncStream<PipelineEvent>.Continuation?
    public init() {}
    public func start(sessionID:UUID,sources:[AudioSource],settings:AppSettings,events:AsyncStream<PipelineEvent>.Continuation) async throws {
        guard let paths=Self.paths(settings) else {
            throw LAIError.message("Descarga Parakeet Redux en Ajustes → Modelos.")
        }
        executable=paths.worker; modelPath=paths.model
        self.sessionID=sessionID; self.events=events
        for source in sources { utterances[source]=Utterance() }
    }
    public static func isAvailable(settings:AppSettings) -> Bool { paths(settings) != nil }

    private static func paths(_ settings:AppSettings) -> (worker:String,model:String)? {
        guard let worker=OptionalModelPackage.fluidWorker(configured:settings.fluidWorker) else { return nil }
        let model=settings.fluidModels.isEmpty ? OptionalModelPackage.parakeet.directory.path:settings.fluidModels
        let directory=URL(fileURLWithPath:model,isDirectory:true)
        let files=["parakeet_vocab.json","Encoder.mlmodelc","Decoder.mlmodelc","JointDecisionv3.mlmodelc","Preprocessor.mlmodelc"]
        guard files.allSatisfy({ FileManager.default.fileExists(atPath:directory.appendingPathComponent($0).path) }) else { return nil }
        return (worker,model)
    }
    public func append(_ chunk:AudioChunk) async throws {
        guard var u=utterances[chunk.source] else { return }
        let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:Utterance.sampleRate,channels:1,interleaved:false)!
        let converter=converters[chunk.source] ?? PCMStreamConverter(); converters[chunk.source]=converter
        let buffer=try converter.buffer(chunk,format:format)
        let samples=Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))
        let rms=sqrt(samples.reduce(Float(0)){$0+$1*$1}/Float(max(1,samples.count)))
        let duration=Double(samples.count)/Utterance.sampleRate
        if u.samples.isEmpty { u.start=chunk.start }
        if rms>0.012 { u.speech=true; u.quiet=0 } else { u.quiet += duration }
        if u.speech { u.samples.append(contentsOf:samples) }
        else if u.samples.count<3200 { u.samples.append(contentsOf:samples) }
        else { u.samples=Array(samples.suffix(3200)); u.start=chunk.start }
        while let window=u.takeFullWindow() {
            utterances[chunk.source]=u
            try await transcribe(window,source:chunk.source)
        }
        utterances[chunk.source]=u
        if u.speech && u.quiet>=0.7 { try await flush(chunk.source) }
    }
    private func flush(_ source:AudioSource) async throws {
        let utterance=utterances.updateValue(Utterance(),forKey:source)
        if let utterance,utterance.speech { try await transcribe(utterance,source:source) }
    }
    private func transcribe(_ u:Utterance,source:AudioSource) async throws {
        let pcm=u.samples.withUnsafeBytes { Data($0) }.base64EncodedString()
        let data=try JSONSerialization.data(withJSONObject:["pcm":pcm])
        let worker=worker; let executable=executable; let models=modelPath
        let reply=try await InferenceGate.shared.perform {
            try await worker.start(executable:executable,arguments:[models])
            do { let result=try await worker.request(data); await worker.stop(); return result }
            catch { await worker.stop(); throw error }
        }
        struct Reply:Decodable { var text:String?; var error:String? }
        let result=try JSONDecoder().decode(Reply.self,from:reply)
        if let error=result.error { throw LAIError.message(error) }
        if let text=result.text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let events {
            try await SpeechEventDelivery.emit(.init(sessionID:sessionID,source:source,start:u.start,end:u.start+Double(u.samples.count)/Utterance.sampleRate,text:text),to:events)
        }
    }
    public func finish() async throws {
        do { for source in Array(utterances.keys) { try await flush(source) }; await worker.stop() }
        catch { await worker.stop(); throw error }
    }
    public func cancel() async { await worker.stop(); utterances.removeAll() }
}
