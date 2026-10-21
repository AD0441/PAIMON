import SwiftUI
import AppKit
import LAICore
@main
struct PaimonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model=AppModel()
    var body: some Scene {
        WindowGroup("PAIMON",id:"main") {
            ContentView(model:model).frame(minWidth:1000,minHeight:650)
                .task {
                    delegate.model=model; await model.bootstrap()
                    #if DEBUG
                    let args=CommandLine.arguments
                    if let index=args.firstIndex(of:"--validate-audio"),args.count>index+2 {
                        model.beginAudioValidation(file:URL(fileURLWithPath:args[index+1]),report:URL(fileURLWithPath:args[index+2]))
                    }
                    #endif
                }
        }
        .defaultSize(width:1240,height:800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("Nueva sesión") { model.newSession() }.keyboardShortcut("n").disabled(model.active)
                Button("Importar audio…") { model.chooseAudioFile() }.keyboardShortcut("o").disabled(model.active)
                Button("Añadir marcador") { Task { await model.addBookmark() } }.keyboardShortcut("m",modifiers:[.command,.shift]).disabled(!model.canAddBookmark)
                Button("Buscar en todas las transcripciones") { model.beginGlobalSearch() }.keyboardShortcut("f",modifiers:[.command,.shift])
                Button(model.state == .paused ? "Reanudar":"Pausar") { Task { await model.pauseOrResume() } }.keyboardShortcut("p",modifiers:[.command,.shift]).disabled(![.recording,.paused].contains(model.state))
            }
        }
        Settings { SettingsView(model:model) }
        MenuBarExtra {
            CaptureMenu(model:model)
        } label: {
            Label(model.state == .recording ? "● \(timestamp(model.elapsed))":model.state == .paused ? "Ⅱ PAIMON":"PAIMON",systemImage:model.state == .recording ? "waveform.circle.fill":"waveform.circle")
                .accessibilityLabel(model.state == .recording ? "PAIMON · Capturando audio":"PAIMON")
        }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    weak var model:AppModel?
    func applicationDidFinishLaunching(_ notification:Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard let model,model.active else { return .terminateNow }
        if model.state == .preparing || model.state == .stopping { return .terminateCancel }
        Task { await model.stopActiveWork(); NSApp.reply(toApplicationShouldTerminate:true) }; return .terminateLater
    }
}
