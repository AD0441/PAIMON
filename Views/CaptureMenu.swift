import SwiftUI
import AppKit
import LAICore
struct CaptureMenu:View {
    var model:AppModel
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        Text(model.ui(model.statusTitle))
        if model.active { Text(timestamp(model.elapsed)) }
        Divider()
        Button("Abrir ventana") { openWindow(id:"main"); NSApp.activate(ignoringOtherApps:true) }
        if model.state == .importing { Button("Cancelar importación") { model.cancelImport() } }
        else if [.recording,.paused].contains(model.state) {
            Button(model.ui(model.state == .paused ? "Reanudar":"Pausar")) { Task { await model.pauseOrResume() } }
            Button("Detener y resumir") { Task { await model.stop() } }
            Button("Añadir marcador") { Task { await model.addBookmark(capture:true) } }
        } else { Button("Iniciar captura") { Task { await model.start() } }.disabled(model.active) }
        Divider(); SettingsLink { Text("Configuración…") }; Divider()
        Button("Salir") { NSApp.terminate(nil) }
    }
}
