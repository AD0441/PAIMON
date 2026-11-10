import Foundation
import AVFoundation
public enum AudioFileTranscriber {
    @discardableResult public static func transcribe(url:URL,settings:AppSettings,sessionID:UUID,events:AsyncStream<PipelineEvent>.Continuation,paceRealtime:Bool=true,engineOverride:(any TranscriptionEngine)?=nil,progress:(@Sendable (Double,Double) async -> Void)?=nil) async throws -> Double {
        try await transcribe(url:url,settings:settings,sessionID:sessionID,events:events,paceRealtime:paceRealtime,engineOverride:engineOverride,progress:progress,diarizer:nil)
    }

    private static func transcribe(url:URL,settings:AppSettings,sessionID:UUID,events:AsyncStream<PipelineEvent>.Continuation,paceRealtime:Bool,engineOverride:(any TranscriptionEngine)?,progress:(@Sendable (Double,Double) async -> Void)?,diarizer:DiarizationSession?) async throws -> Double {
        try Task.checkCancellation()
        let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let engine:any TranscriptionEngine
        if let engineOverride { engine=engineOverride }
        else if settings.transcription == .fluid { engine=FluidSpeechEngine() }
        else if await AppleSpeechEngine.availability(locale:settings.locale)==nil { engine=AppleSpeechEngine() }
        else if settings.transcription == .automatic && !settings.fluidWorker.isEmpty { engine=FluidSpeechEngine() }
        else { throw LAIError.message(await AppleSpeechEngine.availability(locale:settings.locale) ?? "Motor no disponible") }
        try await engine.start(sessionID:sessionID,sources:[.file],settings:settings,events:events)
        do {
            let format=file.processingFormat
            let duration=Double(file.length)/format.sampleRate
            guard duration.isFinite,duration>0 else { throw LAIError.message("El archivo de audio está vacío o no es compatible") }
            guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096) else { throw LAIError.message("No se pudo abrir el audio") }
            let enhanceLevel=settings.enhanceImportedAudio==true
            var leveler=ImportLevelProcessor()
            var lastProgress = -1.0
            var lastProgressTime=ContinuousClock.now
            while file.framePosition<file.length {
                try Task.checkCancellation()
                let position=file.framePosition; try file.read(into:buffer)
                let count=Int(buffer.frameLength)
                guard count>0,let channels=buffer.floatChannelData else { break }
                var samples=[Float](repeating:0,count:count)
                for channel in 0..<Int(format.channelCount) { for i in 0..<count { samples[i] += channels[channel][i]/Float(format.channelCount) } }
                let start=Double(position)/format.sampleRate
                await diarizer?.append(.init(samples:samples,sampleRate:format.sampleRate,start:start,source:.file))
                if enhanceLevel { leveler.process(&samples,sampleRate:format.sampleRate) }
                try await engine.append(.init(samples:samples,sampleRate:format.sampleRate,start:start,source:.file))
                let seconds=Double(file.framePosition)/format.sampleRate
                if (seconds-lastProgress>=0.5 && lastProgressTime.duration(to:.now) >= .milliseconds(300)) || file.framePosition>=file.length {
                    await progress?(seconds,duration); lastProgress=seconds; lastProgressTime = .now
                }
                // Diagnostics retain realtime pacing. Imports apply backpressure
                // in the selected engine and never accumulate the whole file.
                if paceRealtime { try await Task.sleep(for:.seconds(Double(count)/format.sampleRate)) }
            }
            try await engine.finish()
            return duration
        } catch { await engine.cancel(); throw error }
    }
    public static func importSession(url:URL,session:Session,store:SessionStore,events:AsyncStream<PipelineEvent>.Continuation,engineOverride:(any TranscriptionEngine)?=nil,progress:(@Sendable (Double,Double) async -> Void)?=nil) async throws -> Session {
        // Finish the outward stream even if opening/saving the session fails.
        // The UI waits for that stream before completing the import task.
        defer { events.finish() }
        var value=session; value.status="importing"; value.importedFileName=url.lastPathComponent
        try await store.save(value)
        let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingOldest(128))
        defer { pair.continuation.finish(); events.finish() }
        do {
            let duration=try await withThrowingTaskGroup(of:(Double,(any Error)?).self) { group in
                group.addTask {
                    defer { pair.continuation.finish() }
                    let diarizer=DiarizationSession(settings:session.settings,sessionID:session.id,store:store,events:events)
                    do {
                        let duration=try await transcribe(url:url,settings:session.settings,sessionID:session.id,events:pair.continuation,paceRealtime:false,engineOverride:engineOverride,progress:progress,diarizer:diarizer)
                        await diarizer?.finish()
                        return (duration,nil)
                    } catch {
                        await diarizer?.cancel()
                        return (0,error)
                    }
                }
                group.addTask {
                    defer { pair.continuation.finish() }
                    var through=0.0
                    for await event in pair.stream {
                        if case .failure(let message)=event { throw LAIError.message(message) }
                        if case .segment(let segment)=event,segment.isFinal { try await store.append(segment); through=max(through,segment.end) }
                        events.yield(event)
                    }
                    return (through,nil)
                }
                var duration=0.0
                var failure:(any Error)?
                while let result=try await group.next() { duration=max(duration,result.0); if let error=result.1 { failure=error } }
                if let failure { throw failure }
                return duration
            }
            value.duration=duration; value.status="completed"; try await store.save(value)
            return value
        } catch {
            value.status="interrupted"
            value.duration=(try? await store.segments(session:session.id,limit:1,newest:true).last?.1.end) ?? 0
            try? await store.save(value)
            throw error
        }
    }
}

/// Applies a smoothed RMS gain and a soft ceiling to the mono recognition input.
private struct ImportLevelProcessor {
    private var gain:Float?

    mutating func process(_ samples:inout [Float],sampleRate:Double) {
        guard !samples.isEmpty else { return }
        var energy=0.0
        for sample in samples where sample.isFinite {
            let value=Double(sample)
            energy += value*value
        }
        let rms=Float(sqrt(energy/Double(samples.count)))
        // Aim for -20 dBFS RMS with at most +12 dB of makeup gain.
        // Below -50 dBFS, return toward unity instead of chasing quiet noise.
        let target:Float=rms >= 0.00316 ? min(4,max(0.5,0.1/rms)):1
        let previous=gain ?? target
        let responseSeconds=target<previous ? 0.045:0.25
        let duration=Double(samples.count)/sampleRate
        let next=previous+(target-previous)*Float(1-exp(-duration/responseSeconds))
        let increment=(next-previous)/Float(samples.count)
        var currentGain=previous

        let knee:Float=0.70
        let ceiling:Float=0.97
        let headroom=ceiling-knee
        for index in samples.indices {
            currentGain += increment
            let sample=samples[index]
            let amplified=sample.isFinite ? sample*currentGain:0
            let magnitude=abs(amplified)
            if magnitude>knee {
                let compressed=ceiling-headroom/(1+(magnitude-knee)/headroom)
                samples[index]=amplified<0 ? -compressed:compressed
            } else {
                samples[index]=amplified
            }
        }
        gain=next
    }
}
