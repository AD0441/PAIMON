import Foundation
import AVFoundation
// One Parakeet worker/model shared by both sources. Whole utterances, no overlapping
// windows: repetition at artificial overlap boundaries is avoided by construction.
public actor FluidSpeechEngine: TranscriptionEngine {
    struct Utterance { var samples:[Float]=[]; var start:Double=0; var quiet:Double=0; var speech=false }
    private let worker=LocalWorker()
    private var converters:[AudioSource:PCMStreamConverter]=[:]
    private var utterances:[AudioSource:Utterance]=[:]
    private var settings=AppSettings()
    private var sessionID=UUID()
    private var events:AsyncStream<PipelineEvent>.Continuation?
    public init() {}
    public func start(sessionID:UUID,sources:[AudioSource],settings:AppSettings,events:AsyncStream<PipelineEvent>.Continuation) async throws {
        guard FileManager.default.fileExists(atPath:settings.fluidModels+"/parakeet_vocab.json") else { throw LAIError.message("Instala FluidWorker y selecciona la carpeta Parakeet Redux en Configuración") }
        self.sessionID=sessionID; self.events=events; self.settings=settings
        for source in sources { utterances[source]=Utterance() }
    }
    public func append(_ chunk:AudioChunk) async throws {
        guard var u=utterances[chunk.source] else { return }
        let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false)!
        let converter=converters[chunk.source] ?? PCMStreamConverter(); converters[chunk.source]=converter
        let buffer=try converter.buffer(chunk,format:format)
        let samples=Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))
        let rms=sqrt(samples.reduce(Float(0)){$0+$1*$1}/Float(max(1,samples.count)))
        let duration=Double(samples.count)/16000
        if u.samples.isEmpty { u.start=chunk.start }
        if rms>0.012 { u.speech=true; u.quiet=0 } else { u.quiet += duration }
        if u.speech { u.samples.append(contentsOf:samples) }
        else if u.samples.count<3200 { u.samples.append(contentsOf:samples) }
        else { u.samples=Array(samples.suffix(3200)); u.start=chunk.start }
        utterances[chunk.source]=u
        if u.speech && (u.quiet>=0.7 || u.samples.count>=240000) { try await flush(chunk.source) }
    }
    private func flush(_ source:AudioSource) async throws {
        guard let u=utterances[source],u.speech else { utterances[source]=Utterance(); return }
        utterances[source]=Utterance()
        let pcm=u.samples.withUnsafeBytes { Data($0) }.base64EncodedString()
        let data=try JSONSerialization.data(withJSONObject:["pcm":pcm])
        let worker=worker; let executable=settings.fluidWorker; let models=settings.fluidModels
        let reply=try await InferenceGate.shared.perform {
            try await worker.start(executable:executable,arguments:[models])
            do { let result=try await worker.request(data); await worker.stop(); return result }
            catch { await worker.stop(); throw error }
        }
        struct Reply:Decodable { var text:String?; var error:String? }
        let result=try JSONDecoder().decode(Reply.self,from:reply)
        if let error=result.error { throw LAIError.message(error) }
        if let text=result.text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let events {
            try await SpeechEventDelivery.emit(.init(sessionID:sessionID,source:source,start:u.start,end:u.start+Double(u.samples.count)/16000,text:text),to:events)
        }
    }
    public func finish() async throws {
        do { for source in Array(utterances.keys) { try await flush(source) }; await worker.stop() }
        catch { await worker.stop(); throw error }
    }
    public func cancel() async { await worker.stop(); utterances.removeAll() }
}
