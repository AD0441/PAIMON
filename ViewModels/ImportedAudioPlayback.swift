import AVFoundation
import Foundation
import LAICore
import Observation

@MainActor @Observable
final class ImportedAudioPlayback {
    private(set) var isPlaying = false
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var generation = UUID()

    nonisolated static func bookmark(for url: URL) throws -> Data {
        if let scoped = try? url.bookmarkData(options: .withSecurityScope) { return scoped }
        return try url.bookmarkData(options: .minimalBookmark)
    }

    nonisolated static func resolve(_ data: Data) throws -> URL {
        var stale = false
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        if let scoped = try? URL(resolvingBookmarkData: data, options: options.union(.withSecurityScope), relativeTo: nil, bookmarkDataIsStale: &stale) {
            return scoped
        }
        return try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    func play(_ url: URL, start: Double, end: Double) async throws {
        stop()
        let request = generation
        guard url.isFileURL, start.isFinite, end.isFinite, start >= 0, end > start else {
            throw LAIError.message("El intervalo de audio no está disponible.")
        }
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        do {
            let item = AVPlayerItem(url: url)
            let duration = try await item.asset.load(.duration).seconds
            guard request == generation else { return }
            guard duration.isFinite, duration > start else {
                throw LAIError.message("El archivo no contiene ese intervalo de audio.")
            }
            item.forwardPlaybackEndTime = CMTime(seconds: min(end, duration), preferredTimescale: 600)
            let player = AVPlayer(playerItem: item)
            self.player = player
            observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if self?.generation == request { self?.stop() }
                }
            }
            let seeked = await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard request == generation else { return }
            guard seeked else { throw LAIError.message("No se pudo localizar el fragmento de audio.") }
            try Task.checkCancellation()
            isPlaying = true
            player.play()
        } catch {
            guard request == generation else { return }
            stop()
            throw error
        }
    }

    func stop() {
        generation = UUID()
        player?.pause()
        player = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        isPlaying = false
    }
}
