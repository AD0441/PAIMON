import AVFoundation
public enum PCMConverter {
    public static func buffer(_ chunk:AudioChunk,format:AVAudioFormat) throws -> AVAudioPCMBuffer {
        try PCMStreamConverter().buffer(chunk,format:format,ending:true)
    }
}
// Confined to its owning audio/transcription actor. Never shared with callbacks.
public final class PCMStreamConverter {
    private var converter:AVAudioConverter?
    public init() {}
    public func reset() { converter=nil }
    public func buffer(_ chunk:AudioChunk,format:AVAudioFormat,ending:Bool=false) throws -> AVAudioPCMBuffer {
        guard let source=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:chunk.sampleRate,channels:1,interleaved:false),
              let input=AVAudioPCMBuffer(pcmFormat:source,frameCapacity:AVAudioFrameCount(chunk.samples.count)),let channels=input.floatChannelData else { throw LAIError.message("No se pudo crear el búfer PCM") }
        input.frameLength=AVAudioFrameCount(chunk.samples.count)
        chunk.samples.withUnsafeBufferPointer { p in if let base=p.baseAddress { channels[0].update(from:base,count:p.count) } }
        if source==format { return input }
        if converter?.inputFormat != source || converter?.outputFormat != format {
            converter=AVAudioConverter(from:source,to:format); converter?.primeMethod = .none
        }
        guard let converter,let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(ceil(Double(input.frameLength)*format.sampleRate/source.sampleRate))+128) else { throw LAIError.message("Conversión PCM no disponible") }
        var supplied=false; var error:NSError?
        converter.convert(to:output,error:&error) { _,status in
            if supplied { status.pointee = ending ? .endOfStream:.noDataNow; return nil }
            supplied=true; status.pointee = .haveData; return input
        }
        if let error { throw error }
        if ending {
            // Strip EOF filter padding from standalone conversions.
            let expected=AVAudioFrameCount(floor(Double(input.frameLength)*format.sampleRate/source.sampleRate))
            output.frameLength=min(output.frameLength,expected)
        }
        return output
    }
    public func flush() throws -> AVAudioPCMBuffer? {
        guard let converter,let output=AVAudioPCMBuffer(pcmFormat:converter.outputFormat,frameCapacity:1024) else { return nil }
        var error:NSError?
        converter.convert(to:output,error:&error) { _,status in status.pointee = .endOfStream; return nil }
        if let error { throw error }; self.converter=nil; return output
    }
}
