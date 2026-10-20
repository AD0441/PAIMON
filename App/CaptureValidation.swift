#if DEBUG
import Foundation
import AVFoundation
import LAICore
// Explicit debug-only end-to-end test. Real AVAudioPlayer output -> real process
// tap -> real SpeechAnalyzer -> SQLite -> real Foundation Models -> JSON export.
enum ValidationPlayback {
    @concurrent static func play(_ url:URL) async throws {
        let player=try AVAudioPlayer(contentsOf:url)
        guard player.prepareToPlay(),player.play() else { throw LAIError.message("No se pudo reproducir el archivo local de prueba") }
        try await Task.sleep(for:.seconds(player.duration+2))
        player.stop()
    }
}
extension AppModel {
    func beginAudioValidation(file:URL,report:URL) {
        guard validationTask==nil,!validationStarted else { return }
        // The model owns this task; hiding/rebuilding the window must not cancel
        // the test mid-playback and leave an analyzer waiting during cleanup.
        validationTask=Task { [weak self] in
            guard let self else { return }
            await self.validateLocalAudio(file:file,report:report)
            self.validationTask=nil
        }
    }
    func validateLocalAudio(file:URL,report:URL) async {
        guard !active,!validationStarted else { return }; validationStarted=true
        let previous=settings
        let previousSelection=selected
        if let backup=try? JSONEncoder().encode(previous) { UserDefaults.standard.set(backup,forKey:"audioValidationSettingsBackup") }
        defer { settings=previous; UserDefaults.standard.removeObject(forKey:"audioValidationSettingsBackup") }
        settings.systemAudio=true; settings.microphone=false; settings.saveAudio=false
        settings.applicationBundleID=Bundle.main.bundleIdentifier ?? "local.audio.intelligence"
        settings.outputDeviceUID=""; settings.transcription = .apple; settings.summary = .apple; settings.locale="es-ES"
        title="Validación local · audio de prueba"
        let preparationStart=ProcessInfo.processInfo.systemUptime
        await start()
        let preparationSeconds=ProcessInfo.processInfo.systemUptime-preparationStart
        guard state == .recording else {
            try? Data("{\"passed\":false,\"reason\":\"Capture did not start; inspect permissions and model availability\"}".utf8).write(to:report)
            return
        }
        do {
            try await ValidationPlayback.play(file)
            await stop()
            guard let session=current,let store else { throw LAIError.message("No hay una sesión de validación") }
            let rows=try await store.segments(session:session.id,limit:1000)
            let summary=try await store.latestSummary(session:session.id)
            let stats=await captureDiagnostics()
            try await store.save(SessionBookmark(sessionID:session.id,time:3,note:"Nota de validación local"))
            let markers=try await store.bookmarks(session:session.id)
            let hits=try await store.searchTranscripts("cotización viernes",limit:100)
            let searchable=hits.contains{$0.sessionID==session.id}
            let timelineValid=rows.allSatisfy{$0.1.start>=0 && $0.1.end<=session.duration+1} && (rows.first?.1.start ?? .infinity)<5 && session.duration<30
            let result:[String:Any]=["passed":!rows.isEmpty && !(summary?.findings.isEmpty ?? true) && stats.nonzeroBuffers>0 && searchable && markers.count==1 && timelineValid,
                "transcriptSegments":rows.count,"findings":summary?.findings.count ?? 0,
                "searchable":searchable,"bookmarks":markers.count,
                "timelineValid":timelineValid,"durationSeconds":session.duration,"preparationSeconds":preparationSeconds,
                "capturedBuffers":stats.buffers,"capturedFrames":stats.frames,"nonzeroBuffers":stats.nonzeroBuffers,
                "sample":"synthetic local speech, captured from app output by Core Audio process tap",
                "source":"local.audio.intelligence only","audioSaved":false,
                "rssMB":ResourceMetrics.current().residentMB,"footprintMB":ResourceMetrics.current().footprintMB,
                "os":ProcessInfo.processInfo.operatingSystemVersionString,
                "captureState":state.rawValue,"notice":message ?? "","summaryStatus":summaryStatus]
            try await SessionExporter(store:store).export(session:session,to:report.deletingPathExtension().appendingPathExtension("session.json"),format:.json,options:ExportOptions())
            await select(previousSelection)
            try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:report)
        } catch {
            await stop(); message=error.localizedDescription
            try? JSONSerialization.data(withJSONObject:["passed":false,"error":error.localizedDescription],options:[.prettyPrinted]).write(to:report)
        }
    }
}
#endif
