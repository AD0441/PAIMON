import SwiftUI
import AppKit
import LAICore
struct CaptureHeader:View {
    @Bindable var model:AppModel
    @State private var showingContext=false
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
                if model.state == .importing {
                    Button("Cancelar importación",role:.cancel) { model.cancelImport() }.controlSize(.large)
                } else if [.recording,.paused].contains(model.state) {
                    Button { Task { await model.pauseOrResume() } } label: { Label(model.state == .paused ? "Reanudar":"Pausar",systemImage:model.state == .paused ? "play.fill":"pause.fill") }.controlSize(.large)
                    Button(role:.destructive) { Task { await model.stop() } } label: { Label("Detener",systemImage:"stop.fill") }.controlSize(.large)
                } else {
                    Button { model.chooseAudioFile() } label: { Label("Importar audio",systemImage:"square.and.arrow.down") }.controlSize(.large).disabled(model.active || model.store==nil)
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
            if let file=model.selectedSession?.importedFileName {
                Label("Fuente de esta sesión: \(file)",systemImage:"doc.text").font(.caption).foregroundStyle(.secondary)
            }
            if model.state == .importing {
                VStack(alignment:.leading,spacing:5) {
                    ProgressView(value:model.importFraction)
                    Text(model.importFraction>=1 ? "Finalizando reconocimiento y guardado…":"Leído \(timestamp(model.elapsed)) de \(timestamp(model.importDuration)) · transcripción local")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { showingContext=true } label: {
                Label(model.sessionContext.isEmpty ? "Añadir contexto de la sesión":"Editar contexto de la sesión",systemImage:"list.bullet.clipboard")
            }.buttonStyle(.borderless).font(.caption).disabled(model.active || model.summaryWorking).accessibilityIdentifier("editSessionContext")
            if model.settings.microphone && model.settings.systemAudio && !model.active {
                Text("Usa audífonos para evitar que el micrófono vuelva a captar los altavoces. Las dos fuentes se guardan identificadas.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).fixedSize(horizontal:false,vertical:true)
            .sheet(isPresented:$showingContext) { SessionContextEditor(model:model) }
    }
}

private struct SessionContextEditor:View {
    @Bindable var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft=SessionContext()
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Contexto de la sesión").font(.title2.weight(.semibold))
            Text("Orienta el resumen; los hechos deben aparecer en la transcripción.").font(.callout).foregroundStyle(.secondary)
            Form {
                TextField("Objetivo",text:$draft.objective,axis:.vertical).lineLimit(2...2)
                TextField("Temario",text:$draft.agenda,axis:.vertical).lineLimit(3...3)
                TextField("Glosario",text:$draft.glossary,axis:.vertical).lineLimit(2...2)
            }.formStyle(.grouped)
            Text("Objetivo: 250 caracteres · temario: 600 · glosario: 350").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar",role:.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar contexto") {
                    model.sessionContext=draft.bounded
                    Task { await model.saveSessionContext(); dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:560,height:480)
            .onAppear { draft=model.sessionContext }
    }
}
