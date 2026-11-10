import AVFoundation
import Foundation
import SoundAnalysis
import Synchronization

public enum VocalSoundKind: Hashable, Sendable {
    case laughter, applause
    case other(String)

    init(identifier: String) {
        switch identifier {
        case "laughter", "baby_laughter", "giggling", "belly_laugh": self = .laughter
        case "applause", "clapping": self = .applause
        default: self = .other(identifier)
        }
    }

    public var rawValue: String {
        switch self {
        case .laughter: "laughter"
        case .applause: "applause"
        case .other(let identifier): identifier
        }
    }

    public var title: String { VocalSoundAnalysis.categoryName(rawValue) }

    public var symbol: String {
        switch self {
        case .laughter: "face.smiling"
        case .applause: "hands.clap"
        case .other: "waveform"
        }
    }
}

public struct VocalSoundEvent: Identifiable, Sendable {
    public var id: String { "\(kind.rawValue)-\(audioStart)" }
    public let kind: VocalSoundKind
    public let start: Double
    public var end: Double
    public let audioStart: Double
    public var audioEnd: Double
}

public struct VocalSoundReport: Sendable {
    public let events: [VocalSoundEvent]
    public let limited: Bool
}

public enum VocalSoundAnalysis {
    static let minimumConfidence = 0.65
    private static let maxWindows = 2_048
    private static let maxEvents = 200

    public static let defaultIdentifiers: Set<String> = [
        "laughter", "baby_laughter", "giggling", "belly_laugh", "applause", "clapping"
    ]

    public static func categoryName(_ identifier: String) -> String {
        switch identifier {
        case "laughter": "Risa"
        case "baby_laughter": "Risa de bebé"
        case "giggling": "Risita"
        case "belly_laugh": "Carcajada"
        case "applause": "Aplausos"
        case "clapping": "Palmas"
        case "speech": "Habla"
        case "whispering": "Susurro"
        case "shouting": "Gritos"
        case "coughing": "Tos"
        case "sneezing": "Estornudo"
        case "crying": "Llanto"
        case "music": "Música"
        case "dog_bark": "Ladrido"
        case "footsteps": "Pasos"
        case "doorbell": "Timbre"
        default: identifier.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @concurrent
    public static func availableIdentifiers() async throws -> [String] {
        try SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications.sorted()
    }

    @concurrent
    public static func analyze(track: VocalAudioTrack, sessionDuration: Double,
                               identifiers: Set<String> = defaultIdentifiers) async throws -> VocalSoundReport {
        try await InferenceGate.shared.perform {
            try await detect(track: track, sessionDuration: sessionDuration, identifiers: identifiers)
        }
    }

    private static func detect(track: VocalAudioTrack, sessionDuration: Double, identifiers: Set<String>) async throws -> VocalSoundReport {
        let scoped = track.url.startAccessingSecurityScopedResource()
        defer { if scoped { track.url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: track.url)
        let rate = file.processingFormat.sampleRate
        let frames = file.length
        let fileDuration = Double(frames) / rate
        guard fileDuration.isFinite, fileDuration > 0 else {
            throw LAIError.message("El archivo de audio está vacío o no es compatible")
        }
        let duration = sessionDuration.isFinite && sessionDuration > 0 ? sessionDuration : fileDuration
        let analyzer = try FileAnalysis(url: track.url, maxAudioTime: track.isArchived ? fileDuration : min(duration, fileDuration),
                                        identifiers: identifiers)
        let observed = try await analyzer.results()
        let mapped = try await align(observed.windows, track: track, frameCount: frames, rate: rate, duration: duration)
        let events = merge(mapped)
        return VocalSoundReport(events: Array(events.prefix(maxEvents)), limited: observed.limited || events.count > maxEvents)
    }

    struct Window: Sendable {
        let kind: VocalSoundKind
        let start: Double
        let end: Double
    }

    static func align(_ windows: [Window], track: VocalAudioTrack, frameCount: Int64, rate: Double,
                      duration: Double) async throws -> [VocalSoundEvent] {
        let ordered = windows.sorted { $0.start < $1.start }
        var next = 0
        var mapped: [VocalSoundEvent] = []
        try await track.forEachSpan(fileLength: frameCount, rate: rate, duration: duration) { span in
            let lower = Double(span.frame) / rate
            let upper = Double(span.frame + span.count) / rate
            while next < ordered.count, ordered[next].start < upper {
                let window = ordered[next]
                next += 1
                // Reject windows across a splice in a paused or interrupted recording.
                guard window.start >= lower - 0.002, window.end <= upper + 0.002 else { continue }
                let start = max(lower, window.start)
                let end = min(upper, window.end)
                let offset = span.start - lower
                guard start + offset < duration, end > start else { continue }
                let clippedEnd = min(end, duration - offset)
                mapped.append(VocalSoundEvent(kind: window.kind, start: start + offset, end: clippedEnd + offset,
                                             audioStart: start, audioEnd: clippedEnd))
            }
        }
        return mapped
    }

    static func merge(_ windows: [VocalSoundEvent]) -> [VocalSoundEvent] {
        var merged: [VocalSoundEvent] = []
        var last: [VocalSoundKind: Int] = [:]
        for window in windows {
            if let index = last[window.kind], window.start <= merged[index].end + 0.01,
               abs((window.start - window.audioStart) - (merged[index].start - merged[index].audioStart)) <= 0.01 {
                merged[index].end = max(merged[index].end, window.end)
                merged[index].audioEnd = max(merged[index].audioEnd, window.audioEnd)
            } else {
                last[window.kind] = merged.count
                merged.append(window)
            }
        }
        return merged
    }

    private struct Observations {
        var windows: [Window] = []
        var error: (any Error)?
        var limited = false
    }

    private final class Observer: NSObject, SNResultsObserving, Sendable {
        let observations = Mutex(Observations())
        let maxAudioTime: Double
        let identifiers: Set<String>

        init(maxAudioTime: Double, identifiers: Set<String>) {
            self.maxAudioTime = maxAudioTime
            self.identifiers = identifiers
        }

        func request(_ request: any SNRequest, didProduce result: any SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            let start = result.timeRange.start.seconds
            let end = min(maxAudioTime, result.timeRange.end.seconds)
            guard start.isFinite, start >= 0, end.isFinite, end > start else { return }
            var seen: Set<VocalSoundKind> = []
            for label in result.classifications where label.confidence >= VocalSoundAnalysis.minimumConfidence &&
                identifiers.contains(label.identifier) {
                let kind = VocalSoundKind(identifier: label.identifier)
                guard seen.insert(kind).inserted else { continue }
                observations.withLock { value in
                    if value.windows.count < VocalSoundAnalysis.maxWindows {
                        value.windows.append(Window(kind: kind, start: start, end: end))
                    } else {
                        value.limited = true
                    }
                }
            }
        }

        func request(_ request: any SNRequest, didFailWithError error: any Error) {
            observations.withLock { $0.error = error }
        }
        func requestDidComplete(_ request: any SNRequest) {}
    }

    // Start and cancellation are serialized. Results arrive on Apple's callback queue.
    private final class FileAnalysis: @unchecked Sendable {
        private let analyzer: SNAudioFileAnalyzer
        private let observer: Observer
        private let cancelled = Mutex(false)

        init(url: URL, maxAudioTime: Double, identifiers: Set<String>) throws {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let supported = identifiers.intersection(request.knownClassifications)
            guard !supported.isEmpty else {
                throw LAIError.message("Selecciona al menos un sonido disponible en Ajustes.")
            }
            analyzer = try SNAudioFileAnalyzer(url: url)
            observer = Observer(maxAudioTime: maxAudioTime, identifiers: supported)
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 1_000)
            request.overlapFactor = 0.5
            try analyzer.add(request, withObserver: observer)
        }

        func results() async throws -> Observations {
            let completed = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    cancelled.withLock { cancelled in
                        if cancelled { continuation.resume(returning: false) }
                        else { analyzer.analyze { continuation.resume(returning: $0) } }
                    }
                }
            } onCancel: {
                cancelled.withLock { cancelled in
                    cancelled = true
                    analyzer.cancelAnalysis()
                }
            }
            try Task.checkCancellation()
            let result = observer.observations.withLock { $0 }
            if let error = result.error { throw error }
            guard completed else { throw LAIError.message("No se pudo terminar el análisis de eventos.") }
            return result
        }
    }
}
