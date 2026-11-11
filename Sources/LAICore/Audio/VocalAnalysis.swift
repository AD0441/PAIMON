import Accelerate
import AVFoundation
import Foundation

public struct VocalAudioTrack: Sendable, Identifiable {
    public let source: AudioSource
    public let url: URL
    private let timing: URL?
    var isArchived: Bool { timing != nil }
    public var id: AudioSource { source }

    public init(importedAudio url: URL) {
        source = .file
        self.url = url
        timing = nil
    }

    private init(source: AudioSource, url: URL, timing: URL) {
        self.source = source
        self.url = url
        self.timing = timing
    }

    public static func archived(in directory: URL) -> [Self] {
        let timing = directory.appendingPathComponent("timing.jsonl")
        guard FileManager.default.isReadableFile(atPath: timing.path) else { return [] }
        return [AudioSource.system, .microphone].compactMap { source in
            let url = directory.appendingPathComponent(source.rawValue + ".caf")
            guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            return Self(source: source, url: url, timing: timing)
        }
    }

    @concurrent public func playbackRange(start:Double,end:Double) async throws -> ClosedRange<Double>? {
        let file=try AVAudioFile(forReading:url)
        let rate=file.processingFormat.sampleRate
        var result:ClosedRange<Double>?
        try await forEachSpan(fileLength:file.length,rate:rate,duration:max(end,Double(file.length)/rate)) { span in
            guard result==nil,span.start<=start,start<end,end<=span.start+Double(span.count)/rate else { return }
            let audioStart=Double(span.frame)/rate+start-span.start
            result=audioStart...(audioStart+end-start)
        }
        return result
    }

    struct Span {
        var frame: Int64
        var count: Int64
        var start: Double
    }

    private struct ArchiveRow: Decodable {
        let source: AudioSource
        let start: Double
        let frame: Int64
        let frames: Int64
        let sampleRate: Double
    }

    // Only adjacent file frames with a continuous session clock share a span.
    func forEachSpan(fileLength: Int64, rate: Double, duration: Double, flushEvery: Double? = nil,
                     visit: (Span) async throws -> Void) async throws {
        guard let timing else {
            try await visit(Span(frame: 0, count: fileLength, start: 0))
            return
        }
        let decoder = JSONDecoder()
        var pending: Span?
        for try await line in timing.lines {
            try Task.checkCancellation()
            guard let row = try? decoder.decode(ArchiveRow.self, from: Data(line.utf8)),
                  row.source == source, row.start.isFinite, row.start >= 0, row.start < duration,
                  row.sampleRate == rate, row.frame >= 0, row.frame < fileLength, row.frames > 0,
                  row.frames <= fileLength - row.frame else { continue }
            if var span = pending, span.frame + span.count == row.frame,
               abs(span.start + Double(span.count) / rate - row.start) < 0.045 {
                span.count += row.frames
                pending = span
            } else {
                if let span = pending { try await visit(span) }
                pending = Span(frame: row.frame, count: row.frames, start: row.start)
            }
            if let flushEvery, let span = pending, Double(span.count) / rate >= flushEvery {
                try await visit(span)
                pending = nil
            }
        }
        if let span = pending { try await visit(span) }
    }
}

public struct VocalPoint: Identifiable, Sendable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let level: Double
    public let pitch: Double?
    public let pitchVariation: Double?
    public let quietSeconds: Double
    public let measuredSeconds: Double
    public let audioStart: Double
    public let audioEnd: Double

    public var quietPercent: Double { 100 * quietSeconds / measuredSeconds }
}

public enum VocalAnalysis {
    // A description of signal level in dBFS. This is not speech recognition.
    private static let quietLevel = -46.0

    @concurrent
    public static func analyze(
        track: VocalAudioTrack, sessionDuration: Double,
        progress: @Sendable (Double) async -> Void = { _ in }
    ) async throws -> [VocalPoint] {
        try Task.checkCancellation()
        let scoped = track.url.startAccessingSecurityScopedResource()
        defer { if scoped { track.url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: track.url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = file.processingFormat.sampleRate
        let fileLength = file.length
        let fileDuration = Double(fileLength) / rate
        guard fileDuration.isFinite, fileDuration > 0 else {
            throw LAIError.message("El archivo de audio está vacío o no es compatible")
        }
        let duration = sessionDuration.isFinite && sessionDuration > 0
            ? (track.isArchived ? max(sessionDuration, fileDuration) : min(sessionDuration, fileDuration))
            : fileDuration
        let scanner = try Scanner(file: file, duration: duration)

        try await track.forEachSpan(fileLength: fileLength, rate: rate, duration: duration, flushEvery: 8) { span in
            try await scanner.scan(span, progress: progress)
        }
        try Task.checkCancellation()
        await progress(1)
        return scanner.points()
    }

    private struct Bin {
        var start: Double
        var end: Double
        var audioStart: Double
        var audioEnd: Double
        var lastPlaybackEnd: Double
        var frames = 0
        var energy = 0.0
        var quietSeconds = 0.0
        var pitches = 0
        var sumPitch = 0.0
        var squaredPitch = 0.0

        mutating func add(end: Double, fileTime: Double, frames: Int, rate: Double, rms: Double, pitch: Double?) {
            let seconds = Double(frames) / rate
            if abs(audioEnd - fileTime) < 0.001, abs(lastPlaybackEnd - (end - seconds)) < 0.045 {
                audioEnd = min(audioStart + 2, fileTime + seconds)
                lastPlaybackEnd = end
            }
            self.end = max(self.end, end)
            self.frames += frames
            energy += rms * rms * Double(frames)
            if VocalAnalysis.decibels(rms) <= VocalAnalysis.quietLevel { quietSeconds += seconds }
            if let pitch {
                pitches += 1
                sumPitch += pitch
                squaredPitch += pitch * pitch
            }
        }
    }

    private final class Scanner {
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        let fileLength: Int64
        let rate: Double
        let duration: Double
        let interval: Double
        var bins: [Int: Bin] = [:]
        var mono: [Float]
        var pitchBuffer = [Float](repeating: 0, count: 320)
        var correlations = [Float](repeating: 0, count: 125)
        var lastProgress = ContinuousClock.now

        init(file: AVAudioFile, duration: Double) throws {
            self.file = file
            fileLength = file.length
            self.duration = duration
            rate = file.processingFormat.sampleRate
            interval = max(1, ceil(duration / 900))
            guard rate >= 1_000, rate <= 384_000,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount((rate / 10).rounded())) else {
                throw LAIError.message("No se pudo abrir el audio")
            }
            self.buffer = buffer
            mono = [Float](repeating: 0, count: Int(buffer.frameCapacity))
        }

        func scan(_ span: VocalAudioTrack.Span, progress: @Sendable (Double) async -> Void) async throws {
            file.framePosition = span.frame
            let limit = span.frame + span.count
            while file.framePosition < limit {
                try Task.checkCancellation()
                let position = file.framePosition
                let start = span.start + Double(position - span.frame) / rate
                guard start < duration else { break }
                let index = Int(start / interval)
                let until = min(duration, Double(index + 1) * interval)
                let framesToBoundary = max(1, Int64(((until - start) * rate).rounded()))
                let count = AVAudioFrameCount(min(Int64(buffer.frameCapacity), limit - position, framesToBoundary))
                try file.read(into: buffer, frameCount: count)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let channels = buffer.floatChannelData else { break }
                let channelCount = Int(buffer.format.channelCount)
                for index in 0..<frames {
                    var sample: Float = 0
                    for channel in 0..<channelCount { sample += channels[channel][index] }
                    mono[index] = sample.isFinite ? sample / Float(channelCount) : 0
                }
                let rms = Double(vDSP.rootMeanSquare(mono.prefix(frames)))
                let pitch = VocalAnalysis.decibels(rms) > VocalAnalysis.quietLevel ? estimatePitch(frames: frames) : nil
                let fileTime = Double(position) / rate
                let end = start + Double(frames) / rate
                bins[index, default: Bin(start: start, end: start, audioStart: fileTime, audioEnd: fileTime, lastPlaybackEnd: start)]
                    .add(end: end, fileTime: fileTime, frames: frames, rate: rate, rms: rms, pitch: pitch)
                if lastProgress.duration(to: .now) >= .milliseconds(250) {
                    lastProgress = .now
                    await progress(min(1, Double(file.framePosition) / Double(fileLength)))
                }
            }
        }

        func points() -> [VocalPoint] {
            bins.keys.sorted().compactMap { index in
                guard let bin = bins[index], bin.frames > 0 else { return nil }
                let n = Double(bin.pitches)
                let pitch = n > 0 ? bin.sumPitch / n : nil
                let variation = pitch.flatMap { n > 1 ? sqrt(max(0, bin.squaredPitch / n - $0 * $0)) : nil }
                return VocalPoint(id: index, start: bin.start, end: bin.end,
                                  level: VocalAnalysis.decibels(sqrt(bin.energy / Double(bin.frames))),
                                  pitch: pitch, pitchVariation: variation, quietSeconds: bin.quietSeconds,
                                  measuredSeconds: Double(bin.frames) / rate, audioStart: bin.audioStart, audioEnd: bin.audioEnd)
            }
        }

        private func estimatePitch(frames: Int) -> Double? {
            let targetRate = 8_000.0
            let ratio = rate / targetRate
            guard Double(frames - 1) >= Double(pitchBuffer.count - 1) * ratio else { return nil }
            let offset = (Double(frames) - Double(pitchBuffer.count - 1) * ratio - 1) / 2
            for index in pitchBuffer.indices {
                let position = offset + Double(index) * ratio
                let lower = Int(position)
                let upper = min(lower + 1, frames - 1)
                pitchBuffer[index] = mono[lower] + Float(position - Double(lower)) * (mono[upper] - mono[lower])
            }
            let mean = vDSP.mean(pitchBuffer)
            for index in pitchBuffer.indices { pitchBuffer[index] -= mean }
            let lowLag = 17
            let highLag = 123
            let best = pitchBuffer.withUnsafeBufferPointer { data -> Float in
                guard let base = data.baseAddress else { return 0 }
                var best: Float = 0
                for lag in (lowLag - 1)...(highLag + 1) {
                    let length = vDSP_Length(data.count - lag)
                    var cross: Float = 0
                    var first: Float = 0
                    var second: Float = 0
                    vDSP_dotpr(base, 1, base + lag, 1, &cross, length)
                    vDSP_svesq(base, 1, &first, length)
                    vDSP_svesq(base + lag, 1, &second, length)
                    let score = first > 0 && second > 0 ? cross / sqrt(first * second) : 0
                    correlations[lag] = score
                    best = max(best, score)
                }
                return best
            }
            let threshold = max(0.72, best * 0.9)
            for lag in lowLag...highLag where correlations[lag] >= threshold &&
                correlations[lag] >= correlations[lag - 1] && correlations[lag] > correlations[lag + 1] {
                return targetRate / Double(lag)
            }
            return nil
        }
    }

    private static func decibels(_ rms: Double) -> Double {
        min(0, max(-80, 20 * log10(max(0.0001, rms))))
    }
}
