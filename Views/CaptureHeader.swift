import SwiftUI
import AppKit
import LAICore
struct CaptureHeader:View {
    @Bindable var model:AppModel
    private var apps:[NSRunningApplication] { NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.sorted{($0.localizedName ?? "")<($1.localizedName ?? "")} }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:5) {
                    if !model.active {
                        TextField("Nombre de la sesión",text:$model.title).font(.title2.weight(.semibold)).textFieldStyle(.plain).onSubmit { Task { await model.rename() } }
                    } else { Text(model.selectedSession?.title ?? "Sesión").font(.title2.weight(.semibold)).textSelection(.enabled) }
                    HStack(spacing:8) {
                        Circle().fill(model.state == .recording ? .red:model.state == .paused ? .orange:.secondary).frame(width:7,height:7)
                        Text(model.statusTitle).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(timestamp(model.active ? model.elapsed:model.selectedSession?.duration ?? 0)).monospacedDigit().foregroundStyle(.secondary)
                    }.font(.callout)
                }
                Spacer()
                if [.recording,.paused].contains(model.state) {
                    Button { Task { await model.pauseOrResume() } } label: { Label(model.state == .paused ? "Reanudar":"Pausar",systemImage:model.state == .paused ? "play.fill":"pause.fill") }.controlSize(.large)
                    Button(role:.destructive) { Task { await model.stop() } } label: { Label("Detener",systemImage:"stop.fill") }.controlSize(.large)
                } else {
                    Button { Task { await model.start() } } label: { Label(model.state == .preparing ? "Preparando…":"Iniciar",systemImage:"record.circle") }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.active || model.store==nil)
                        .keyboardShortcut("r",modifiers:[.command,.shift])
                }
                if model.state == .preparing || model.state == .stopping { ProgressView().controlSize(.small) }
            }
            HStack(spacing:16) {
                Toggle("Sistema",isOn:$model.settings.systemAudio).toggleStyle(.checkbox)
                Picker("Fuente",selection:$model.settings.applicationBundleID) {
                    Text("Todo el sistema").tag("")
                    ForEach(apps,id:\.processIdentifier) { app in if let id=app.bundleIdentifier { Text(app.localizedName ?? id).tag(id) } }
                }.frame(maxWidth:300).disabled(!model.settings.systemAudio)
                Toggle("Micrófono",isOn:$model.settings.microphone).toggleStyle(.checkbox)
                Picker("Plantilla",selection:Binding(get:{model.selectedTemplate},set:{value in Task { await model.setSummaryTemplate(value) }})) {
                    ForEach(SummaryTemplate.allCases) { template in Text(template.title).tag(template) }
                }.frame(maxWidth:230).disabled(model.summaryWorking)
                Spacer()
                ForEach([AudioSource.system,.microphone],id:\.self) { source in
                    if (source == .system && model.settings.systemAudio) || (source == .microphone && model.settings.microphone) {
                        HStack(spacing:5) {
                            Image(systemName:source == .system ? "speaker.wave.2":"mic")
                            Capsule().fill(model.voice[source]==true ? Color.green:Color.secondary.opacity(0.25)).frame(width:max(5,CGFloat(model.levels[source] ?? 0)*120),height:5).frame(width:35,alignment:.leading)
                        }.font(.caption).help(source.title)
                    }
                }
            }.font(.callout).disabled(model.active)
            if model.settings.microphone && model.settings.systemAudio && !model.active {
                Text("Usa audífonos para evitar que el micrófono vuelva a captar los altavoces. Las dos fuentes se guardan identificadas.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20)
    }
}
