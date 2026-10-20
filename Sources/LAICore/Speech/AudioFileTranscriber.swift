import Foundation
import AVFoundation
public enum AudioFileTranscriber {
    public static func transcribe(url:URL,settings:AppSettings,sessionID:UUID,events:AsyncStream<PipelineEvent>.Continuation) async throws {
        let engine:any TranscriptionEngine = settings.transcription == .fluid ? FluidSpeechEngine():AppleSpeechEngine()
        try await engine.start(sessionID:sessionID,sources:[.file],settings:settings,events:events)
        do {
            let file=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
            let format=file.processingFormat
            guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096) else { throw LAIError.message("No se pudo abrir el audio") }
            while file.framePosition<file.length {
                try Task.checkCancellation()
                let position=file.framePosition; try file.read(into:buffer)
                let count=Int(buffer.frameLength)
                guard count>0,let channels=buffer.floatChannelData else { break }
                var samples=[Float](repeating:0,count:count)
                for channel in 0..<Int(format.channelCount) { for i in 0..<count { samples[i] += channels[channel][i]/Float(format.channelCount) } }
                try await engine.append(.init(samples:samples,sampleRate:format.sampleRate,start:Double(position)/format.sampleRate,source:.file))
                // Pace test-file input so the same bounded realtime stream cannot overrun.
                try await Task.sleep(for:.seconds(Double(count)/format.sampleRate))
            }
            try await engine.finish()
        } catch { await engine.cancel(); throw error }
    }
}
