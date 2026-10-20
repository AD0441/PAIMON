import SwiftUI
import LAICore
struct SettingsView:View {
    @Bindable var model:AppModel
    var body:some View {
        TabView {
            Form {
                Section("Reconocimiento de voz") {
                    Picker("Motor",selection:$model.settings.transcription) { Text("Automático: Apple → Parakeet").tag(TranscriptionBackend.automatic); Text("Apple SpeechTranscriber").tag(TranscriptionBackend.apple); Text("FluidAudio · Parakeet Redux").tag(TranscriptionBackend.fluid) }
                    Picker("Idioma de Apple",selection:$model.settings.locale) { Text("Español").tag("es-ES"); Text("English").tag("en-US") }
                    Text("Parakeet detecta el idioma automáticamente. SpeechTranscriber de macOS 26 usa el idioma seleccionado.").font(.caption).foregroundStyle(.secondary)
                    Text(model.speechStatus).font(.caption).textSelection(.enabled)
                }
                Section("Resumen") {
                    Picker("Plantilla para nuevas sesiones",selection:Binding(get:{model.settings.summaryTemplate ?? .meeting},set:{model.settings.summaryTemplate=$0})) {
                        ForEach(SummaryTemplate.allCases) { template in Text(template.title).tag(template) }
                    }
                    Picker("Motor local",selection:$model.settings.summary) { Text("Apple Foundation Models").tag(SummaryBackend.apple); Text("MLX opcional").tag(SummaryBackend.mlx) }
                    Picker("Actualizar cada",selection:$model.settings.summaryInterval) { Text("1 minuto").tag(60.0); Text("3 minutos").tag(180.0); Text("5 minutos").tag(300.0); Text("10 minutos").tag(600.0) }
                    Text("Si se acumula mucho texto, el resumen puede adelantarse después de un minuto. Los silencios no generan inferencias.").font(.caption).foregroundStyle(.secondary)
                    Text(model.summaryStatus).font(.caption).textSelection(.enabled)
                }
                Button("Comprobar disponibilidad") { Task { await model.checkAvailability() } }
            }.formStyle(.grouped).tabItem { Label("Inteligencia",systemImage:"sparkles") }
            Form {
                Section("Dispositivos") {
                    Picker("Micrófono",selection:$model.settings.microphoneDevice) { Text("Predeterminado").tag(UInt32(0)); ForEach(AudioHardware.devices(input:true)) { Text($0.name).tag($0.id) } }
                    Picker("Salida capturada",selection:$model.settings.outputDeviceUID) { Text("Todas las salidas").tag(""); ForEach(AudioHardware.devices(input:false)) { Text($0.name).tag($0.uid) } }
                }
                Section("Privacidad y almacenamiento") {
                    Toggle("Guardar audio de próximas sesiones",isOn:$model.settings.saveAudio)
                    Text("Desactivado por defecto. El audio opcional se escribe en disco por fuente, con un archivo de sincronización.").font(.caption).foregroundStyle(.secondary)
                    Button("Abrir almacenamiento local") { model.revealStorage() }
                }
                Section("Rendimiento") {
                    Toggle("Posponer resúmenes con presión de recursos",isOn:$model.settings.energySaving)
                    Text("300 fragmentos, 120 hallazgos por página y una generación de resumen a la vez. Los finales pendientes se recuperan cuando baja la presión o al volver a abrir PAIMON.").font(.caption).foregroundStyle(.secondary)
                    Text("Los tiempos, errores y recursos del resumen se registran solo en SQLite local; no incluyen texto ni audio.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).disabled(model.active).tabItem { Label("Audio y memoria",systemImage:"waveform") }
            Form {
                Section("Recursos de Apple") {
                    Button("Autorizar descarga del idioma seleccionado") { Task { await model.installSpeech() } }
                    Text("La descarga es la única operación de red de esta aplicación. Apple Intelligence se configura desde Ajustes del Sistema.").font(.caption).foregroundStyle(.secondary)
                }
                Section("FluidAudio · instalación opcional") {
                    pathRow("FluidWorker",key:\.fluidWorker,folder:false)
                    pathRow("Carpeta Parakeet Redux",key:\.fluidModels,folder:true)
                    Text("Ejecuta script/prepare_fluid.sh para compilar el motor. Los modelos se preparan por separado y no se descargan al iniciar una sesión.").font(.caption).foregroundStyle(.secondary)
                }
                Section("MLX · instalación opcional") {
                    pathRow("Python de MLX",key:\.mlxPython,folder:false)
                    pathRow("mlx_summary.py",key:\.mlxScript,folder:false)
                    pathRow("Modelo cuantizado local",key:\.mlxModel,folder:true)
                    Text("Instalación explícita con script/prepare_mlx.sh. Recomendado: Qwen2.5 1.5B Instruct 4 bit. MLX usa GPU Metal; no ANE.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).disabled(model.active).tabItem { Label("Modelos",systemImage:"shippingbox") }
        }.padding(12).frame(width:680,height:590)
    }
    private func pathRow(_ title:String,key:WritableKeyPath<AppSettings,String>,folder:Bool) -> some View {
        HStack { TextField(title,text:Binding(get:{model.settings[keyPath:key]},set:{model.settings[keyPath:key]=$0})); Button("Elegir…") { model.choosePath(key,folder:folder) } }
    }
}
