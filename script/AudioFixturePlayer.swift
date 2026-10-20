import AppKit
import AVFoundation

// Explicit test tool. It only plays the bundled synthetic fixture, allowing the
// installed Release app to capture this process without listening to other apps.
@MainActor final class FixturePlayerDelegate:NSObject,NSApplicationDelegate {
    private var window:NSWindow?
    private var player:AVAudioPlayer?
    private let status=NSTextField(labelWithString:"Muestra sintética local · no captura audio")
    func applicationDidFinishLaunching(_ notification:Notification) {
        let button=NSButton(title:"Reproducir muestra",target:self,action:#selector(playSample))
        let content=NSStackView(views:[status,button]); content.orientation = .vertical; content.spacing=20
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:460,height:180),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="PAIMON Audio Fixture"; window.contentView=content; window.center()
        self.window=window; window.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    @objc private func playSample() {
        do {
            guard let file=Bundle.main.url(forResource:"sample",withExtension:"aiff") else { throw CocoaError(.fileNoSuchFile) }
            let player=try AVAudioPlayer(contentsOf:file)
            guard player.prepareToPlay(),player.play() else { throw CocoaError(.fileReadUnknown) }
            self.player=player; status.stringValue="Reproduciendo voz sintética local (unos 9 segundos)"
        } catch { status.stringValue="No se pudo reproducir: \(error.localizedDescription)" }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
@main enum FixturePlayer {
    @MainActor static func main() {
        let app=NSApplication.shared; let delegate=FixturePlayerDelegate()
        app.delegate=delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
