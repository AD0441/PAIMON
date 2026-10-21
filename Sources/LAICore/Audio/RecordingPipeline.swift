import Foundation
import AVFoundation
public actor RecordingPipeline {
    public let store:SessionStore
    private let capture=AudioCaptureService()
    private var engine:(any TranscriptionEngine)?
    private var session:Session?
    private var epoch:Double=0
    private var producer:Task<Void,Never>?
    private var consumer:Task<Void,Never>?
    private var eventTask:Task<Void,Never>?
    private var audioInput:AsyncStream<AudioChunk>.Continuation?
    private var speechEvents:AsyncStream<PipelineEvent>.Continuation?
    private var outward:AsyncStream<PipelineEvent>.Continuation?
    private var archive:AudioArchive?
    public init(store:SessionStore) { self.store=store }
    public func start(title:String,settings:AppSettings,context:SessionContext?=nil) async throws -> (Session,AsyncStream<PipelineEvent>) {
        guard session==nil else { throw LAIError.message("Ya hay una sesión activa") }
        guard settings.systemAudio || settings.microphone else { throw LAIError.message("Selecciona al menos una fuente de audio") }
        let selected:any TranscriptionEngine
        if settings.transcription == .fluid { selected=FluidSpeechEngine() }
        else if await AppleSpeechEngine.availability(locale:settings.locale)==nil { selected=AppleSpeechEngine() }
        else if settings.transcription == .automatic && !settings.fluidWorker.isEmpty { selected=FluidSpeechEngine() }
        else { throw LAIError.message(await AppleSpeechEngine.availability(locale:settings.locale) ?? "Motor no disponible") }
        var value=Session(title:title.isEmpty ? "Nueva sesión":title,settings:settings)
        value.context=context?.bounded
        let events=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingOldest(256))
        let ui=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(128))
        let audio=AsyncStream<AudioChunk>.makeStream(bufferingPolicy:.bufferingOldest(256))
        outward=ui.continuation; speechEvents=events.continuation; audioInput=audio.continuation
        try await store.save(value)
        let persistence=store
        eventTask=Task { @concurrent in
            var recent:[TranscriptSegment]=[]
            for await event in events.stream {
                var forwarded=event
                if case .segment(var segment)=event,segment.isFinal {
                    func normalized(_ value:String) -> String { value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:nil).components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.joined(separator:" ") }
                    let words=normalized(segment.text)
                    if words.split(separator:" ").count>=5,let echo=recent.last(where:{ $0.source != segment.source && min($0.end,segment.end)>max($0.start,segment.start) && normalized($0.text)==words }) { segment.duplicateOf=echo.id }
                    recent.append(segment); if recent.count>24 { recent.removeFirst() }
                    forwarded = .segment(segment)
                    do { try await persistence.append(segment) }
                    catch { ui.continuation.yield(.failure("No se pudo guardar: \(error.localizedDescription)")) }
                }
                ui.continuation.yield(forwarded)
            }
        }
        var sources:[AudioSource]=[]
        if settings.systemAudio { sources.append(.system) }; if settings.microphone { sources.append(.microphone) }
        do {
            try await selected.start(sessionID:value.id,sources:sources,settings:settings,events:events.continuation)
            epoch=ProcessInfo.processInfo.systemUptime
            try await capture.start(settings:settings,epoch:epoch)
            epoch=await capture.beginTimeline()
            value.created=Date()
            try await store.save(value)
        } catch {
            await selected.cancel(); _=await capture.stop(); events.continuation.finish(); await eventTask?.value
            ui.continuation.finish(); var failed=value; failed.status="failed"; try? await store.save(failed); throw error
        }
        session=value; engine=selected
        if settings.saveAudio { archive=AudioArchive(directory:store.directory.appendingPathComponent(value.id.uuidString)) }
        let audioArchive=archive
        consumer=Task { @concurrent in
            var detectors:[AudioSource:VAD]=[:]; var lastMeter:[AudioSource:Double]=[:]
            do {
                for await chunk in audio.stream {
                    var detector=detectors[chunk.source] ?? VAD(); let (level,active)=detector.process(chunk.samples,sampleRate:chunk.sampleRate); detectors[chunk.source]=detector
                    if chunk.start-(lastMeter[chunk.source] ?? -1)>=0.1 { ui.continuation.yield(.activity(chunk.source,level,active)); lastMeter[chunk.source]=chunk.start }
                    try await audioArchive?.append(chunk)
                    try await selected.append(chunk)
                }
            } catch { ui.continuation.yield(.failure("Procesamiento interrumpido: \(error.localizedDescription). Detén la sesión para conservar lo reconocido.")) }
        }
        startProducer()
        return (value,ui.stream)
    }
    private func startProducer() {
        guard let input=audioInput,let outward else { return }
        let capture=capture
        producer=Task { @concurrent in
            var lastDrops:UInt64=0
            while !Task.isCancelled {
                for chunk in await capture.drain() {
                    if case .dropped = input.yield(chunk) { outward.yield(.warning("La cola de audio se llenó; existe un intervalo sin transcribir")) }
                }
                let drops=await capture.droppedBuffers()
                if drops>lastDrops { outward.yield(.warning("\(drops) búferes perdidos en captura")); lastDrops=drops }
                do { try await Task.sleep(for:.milliseconds(40)) } catch { break }
            }
        }
    }
    public func pause() async {
        // HAL teardown can wait on permissions or a device. Freeze the clock
        // at the user's action, before awaiting producer/capture shutdown.
        let duration=ProcessInfo.processInfo.systemUptime-epoch
        producer?.cancel(); await producer?.value; producer=nil
        let remaining=await capture.stop(); for chunk in remaining { audioInput?.yield(chunk) }
        if var value=session { value.status="paused"; value.duration=duration; session=value; try? await store.save(value) }
    }
    public func resume() async throws {
        guard let value=session else { return }
        try await capture.start(settings:value.settings,epoch:epoch); startProducer()
        var active=value; active.status="recording"; session=active; try await store.save(active)
    }
    public func captureDiagnostics() async -> CaptureDiagnostics { await capture.captureDiagnostics() }
    public func checkpoint() async throws {
        guard var value=session else { return }; value.duration=ProcessInfo.processInfo.systemUptime-epoch; session=value; try await store.save(value)
    }
    public func stop() async throws -> Session? {
        guard var value=session else { return nil }
        // Capture shutdown, like ASR finalization, may outlive the recording.
        value.duration=ProcessInfo.processInfo.systemUptime-epoch
        producer?.cancel(); await producer?.value; producer=nil
        for chunk in await capture.stop() { audioInput?.yield(chunk) }
        audioInput?.finish(); await consumer?.value; consumer=nil
        var failure:(any Error)?
        do { try await engine?.finish() } catch { failure=error; await engine?.cancel() }
        speechEvents?.finish(); await eventTask?.value; eventTask=nil
        await archive?.close(); archive=nil; engine=nil
        value.status=failure==nil ? "completed":"interrupted"
        try await store.save(value); session=nil
        outward?.finish(); outward=nil
        if let failure { throw failure }; return value
    }
}
