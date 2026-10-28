import SwiftUI
import AppKit
import LAICore
@main
struct PaimonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model=PaimonApp.makeModel()
    private static func makeModel() -> AppModel {
        #if PAIMON_REVIEW
        // This code is absent from the distributed build. All review state,
        // including credentials, is separate from the user's installation.
        let args=CommandLine.arguments
        guard let index=args.firstIndex(of:"--review-directory"),args.count>index+1,
              let preferences=UserDefaults(suiteName:"local.audio.intelligence.review.preferences") else {
            fatalError("La instancia de revisión requiere --review-directory.")
        }
        let directory=URL(fileURLWithPath:args[index+1],isDirectory:true)
        var settings=AppSettings.load(from:preferences); settings.googleEnabled=false; settings.save(to:preferences)
        do { return AppModel(store:try SessionStore(directory:directory),preferences:preferences,googleClient:GoogleAIClient(keychainService:"local.audio.intelligence.review.google-ai")) }
        catch { fatalError("No se pudo abrir el almacenamiento aislado: \(error)") }
        #else
        return AppModel()
        #endif
    }
    var body: some Scene {
        WindowGroup("PAIMON",id:"main") {
            ContentView(model:model).frame(minWidth:1000,minHeight:650)
                .task {
                    delegate.model=model; await model.bootstrap()
                    #if PAIMON_REVIEW
                    let reviewArgs=CommandLine.arguments
                    if !model.validationStarted,let index=reviewArgs.firstIndex(of:"--review-audio"),reviewArgs.count>index+1 {
                        model.validationStarted=true
                        model.beginImport(URL(fileURLWithPath:reviewArgs[index+1]))
                    }
                    #endif
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
                Button(model.ui("Nueva sesión")) { model.newSession() }.keyboardShortcut("n").disabled(model.active)
                Button(model.ui("Importar audio…")) { model.chooseAudioFile() }.keyboardShortcut("o").disabled(model.active)
                Button(model.ui("Añadir marcador")) { Task { await model.addBookmark() } }.keyboardShortcut("m",modifiers:[.command,.shift]).disabled(!model.canAddBookmark)
                Button(model.ui("Buscar en todas las transcripciones")) { model.beginGlobalSearch() }.keyboardShortcut("f",modifiers:[.command,.shift])
                Button(model.ui(model.state == .paused ? "Reanudar":"Pausar")) { Task { await model.pauseOrResume() } }.keyboardShortcut("p",modifiers:[.command,.shift]).disabled(![.recording,.paused].contains(model.state))
            }
        }
        Settings { SettingsView(model:model) }
        MenuBarExtra {
            CaptureMenu(model:model).modifier(AppTheme(palette:model.settings.colorPalette ?? .petroleum,language:model.settings.interfaceLanguage ?? .spanish))
        } label: {
            Label(model.state == .recording ? "● \(timestamp(model.elapsed))":model.state == .paused ? "Ⅱ PAIMON":"PAIMON",systemImage:model.state == .recording ? "waveform.circle.fill":"waveform.circle")
                .accessibilityLabel(model.state == .recording ? "PAIMON · Capturando audio":"PAIMON")
        }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    weak var model:AppModel?
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let url=Bundle.main.url(forResource:"Paimon",withExtension:"icns"),let image=NSImage(contentsOf:url) { NSApp.applicationIconImage=image }
        #if PAIMON_REVIEW
        if CommandLine.arguments.contains("--review-dark") { NSApp.appearance=NSAppearance(named:.darkAqua) }
        #endif
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard let model,model.active else { return .terminateNow }
        if model.state == .preparing || model.state == .stopping { return .terminateCancel }
        Task { await model.stopActiveWork(); NSApp.reply(toApplicationShouldTerminate:true) }; return .terminateLater
    }
}
