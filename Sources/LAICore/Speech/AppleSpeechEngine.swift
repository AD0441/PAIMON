import Foundation
import Speech
import AVFoundation
import CoreMedia
public actor AppleSpeechEngine: TranscriptionEngine {
    private struct Stream {
        var analyzer: SpeechAnalyzer
        var input: AsyncStream<AnalyzerInput>.Continuation
        var results: Task<Void, any Error>
        var format: AVAudioFormat
        var nextFrame:Int64=0
        var lastInputEnd:Double?
        var converter=PCMStreamConverter()
    }
    private var streams:[AudioSource:Stream]=[:]
    private var locale:Locale?
    public init() {}
    public static func availability(locale identifier: String) async -> String? {
        guard SpeechTranscriber.isAvailable else { return "SpeechTranscriber no está disponible en este equipo" }
        guard let locale=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:identifier)) else { return "SpeechTranscriber no admite \(identifier)" }
        let module=SpeechTranscriber(locale:locale,preset:.timeIndexedProgressiveTranscription)
        let installed=await SpeechTranscriber.installedLocales
        let status=await AssetInventory.status(forModules:[module])
        guard installed.contains(locale) || status == .installed else { return "Faltan los recursos de voz para \(locale.identifier). Descárgalos en Configuración → Modelos." }
        return nil
    }
    public static func install(locale identifier: String) async throws {
        guard let locale=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:identifier)) else { throw LAIError.message("Idioma no admitido") }
        let module=SpeechTranscriber(locale:locale,preset:.timeIndexedProgressiveTranscription)
        if let request=try await AssetInventory.assetInstallationRequest(supporting:[module]) { try await request.downloadAndInstall() }
    }
    public func start(sessionID: UUID, sources: [AudioSource], settings: AppSettings, events: AsyncStream<PipelineEvent>.Continuation) async throws {
        if let reason=await Self.availability(locale:settings.locale) { throw LAIError.message(reason) }
        guard let resolved=await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:settings.locale)) else { throw LAIError.message("Idioma no disponible") }
        locale=resolved; try await AssetInventory.reserve(locale:resolved)
        do {
            for source in sources {
                let module=SpeechTranscriber(locale:resolved,preset:.timeIndexedProgressiveTranscription)
                guard let format=await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[module]) else { throw LAIError.message("SpeechAnalyzer no ofrece un formato compatible") }
                let pair=AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingOldest(48))
                let analyzer=SpeechAnalyzer(modules:[module],options:.init(priority:.utility,modelRetention:.whileInUse))
                let results=Task { @concurrent in
                    do {
                        for try await result in module.results {
                            let text=String(result.text.characters).trimmingCharacters(in:.whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }
                            try await SpeechEventDelivery.emit(.init(sessionID:sessionID,source:source,start:CMTimeGetSeconds(result.range.start),end:CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)),text:text,isFinal:result.isFinal),to:events)
                        }
                    } catch { if !Task.isCancelled { events.yield(.failure("Speech: \(error.localizedDescription)")) }; throw error }
                }
                streams[source]=Stream(analyzer:analyzer,input:pair.continuation,results:results,format:format)
                try await analyzer.prepareToAnalyze(in:format)
                try await analyzer.start(inputSequence:pair.stream)
            }
        } catch { await cancel(); throw error }
    }
    public func append(_ chunk: AudioChunk) async throws {
        guard var stream=streams[chunk.source], !chunk.samples.isEmpty else { return }
        let rate=Int32(stream.format.sampleRate.rounded())
        if stream.lastInputEnd==nil || abs(chunk.start-(stream.lastInputEnd ?? chunk.start))>0.15 {
            stream.converter.reset(); stream.nextFrame=Int64((chunk.start*Double(rate)).rounded())
        }
        stream.lastInputEnd=chunk.start+Double(chunk.samples.count)/chunk.sampleRate
        let buffer=try stream.converter.buffer(chunk,format:stream.format)
        guard buffer.frameLength>0 else { streams[chunk.source]=stream; return }
        if ProcessInfo.processInfo.environment["LAI_DIAGNOSTICS"]=="1" { print("INPUT \(chunk.start) \(buffer.frameLength) \(buffer.format)") }
        let frame=stream.nextFrame
        let input=AnalyzerInput(buffer:buffer,bufferStartTime:CMTime(value:frame,timescale:rate))
        stream.nextFrame=frame+Int64(buffer.frameLength)
        streams[chunk.source]=stream
        switch stream.input.yield(input) {
        case .dropped: throw LAIError.message("El reconocimiento no alcanza la velocidad del audio; se ha alcanzado el límite de la cola")
        case .terminated: throw LAIError.message("El motor de voz se ha detenido")
        case .enqueued: break
        @unknown default: break
        }
    }
    public func finish() async throws {
        var failure:(any Error)?
        for stream in streams.values {
            do {
                if let tail=try stream.converter.flush(),tail.frameLength>0 {
                    let rate=Int32(stream.format.sampleRate.rounded())
                    let remaining=max(0,Int64(((stream.lastInputEnd ?? 0)*Double(rate)).rounded())-stream.nextFrame)
                    tail.frameLength=min(tail.frameLength,AVAudioFrameCount(remaining))
                    if tail.frameLength>0 { stream.input.yield(AnalyzerInput(buffer:tail,bufferStartTime:CMTime(value:stream.nextFrame,timescale:rate))) }
                }
            } catch { failure=error }
            stream.input.finish()
            do { try await stream.analyzer.finalizeAndFinishThroughEndOfInput() }
            catch {
                failure=error
                // A cancelled finalization may leave module.results open. Stop
                // it explicitly before waiting, including when Stop's caller
                // was cancelled by the lifecycle of a SwiftUI task.
                stream.results.cancel()
                await stream.analyzer.cancelAndFinishNow()
            }
            do { try await stream.results.value } catch { failure=error }
        }
        streams.removeAll()
        if let locale { await AssetInventory.release(reservedLocale:locale) }; locale=nil
        if let failure { throw failure }
    }
    public func cancel() async {
        for stream in streams.values { stream.input.finish(); stream.results.cancel(); await stream.analyzer.cancelAndFinishNow(); _=try? await stream.results.value }
        streams.removeAll()
        if let locale { await AssetInventory.release(reservedLocale:locale) }; locale=nil
    }
}
