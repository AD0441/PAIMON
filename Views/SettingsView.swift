import SwiftUI
import AppKit
import LAICore
struct SettingsView:View {
    @Bindable var model:AppModel
    @State private var googleKey=""
    var body:some View {
        TabView {
            Form {
                Section("Reconocimiento de voz") {
                    Picker("Motor",selection:$model.settings.transcription) { Text("Automático: Apple → Parakeet").tag(TranscriptionBackend.automatic); Text("Apple SpeechTranscriber").tag(TranscriptionBackend.apple); Text("FluidAudio · Parakeet Redux").tag(TranscriptionBackend.fluid) }
                    Picker("Idioma de Apple",selection:$model.settings.locale) { Text("Español").tag("es-ES"); Text("English").tag("en-US") }
                    Text("Parakeet detecta el idioma automáticamente. SpeechTranscriber de macOS 26 usa el idioma seleccionado.").font(.caption).foregroundStyle(.secondary)
                    Text(model.ui(model.speechStatus)).font(.caption).textSelection(.enabled)
                }
                Section("Resumen") {
                    Picker("Plantilla para nuevas sesiones",selection:Binding(get:{model.settings.summaryTemplate ?? .meeting},set:{model.settings.summaryTemplate=$0})) {
                        ForEach(SummaryTemplate.allCases) { template in Text(LocalizedStringKey(template.title)).tag(template) }
                    }
                    Picker("Motor local",selection:$model.settings.summary) { Text("Apple Foundation Models").tag(SummaryBackend.apple); Text("MLX opcional").tag(SummaryBackend.mlx) }
                    Picker("Actualizar cada",selection:$model.settings.summaryInterval) { Text("1 minuto").tag(60.0); Text("3 minutos").tag(180.0); Text("5 minutos").tag(300.0); Text("10 minutos").tag(600.0) }
                    Text("Si se acumula mucho texto, el resumen puede adelantarse después de un minuto. Los silencios no generan inferencias.").font(.caption).foregroundStyle(.secondary)
                    Text(model.ui(model.summaryAvailability)).font(.caption).textSelection(.enabled)
                }
                Button("Comprobar disponibilidad") { Task { await model.checkAvailability() } }
            }.formStyle(.grouped).tabItem { Label("Inteligencia",systemImage:"sparkles") }
            Form {
                Section("Google AI · opcional") {
                    Toggle("Usar Google AI para resumir nuevas sesiones",isOn:Binding(get:{model.settings.googleEnabled==true},set:{ value in Task { await model.setGoogleEnabled(value) } })).toggleStyle(.checkbox).accessibilityIdentifier("enableGoogleAI")
                    Text("Al seleccionarlo se envían fragmentos de transcripción, contexto y resúmenes previos a Google. El reconocimiento de voz y el audio permanecen en el Mac. Requiere Internet y utiliza la cuota de tu proyecto de Google.").font(.caption).foregroundStyle(.secondary)
                    Text("Las sesiones anteriores conservan su motor. Puedes seleccionar Google AI en el panel Resumen de cada sesión.").font(.caption).foregroundStyle(.secondary)
                    Link("Crear o administrar una clave en Google AI Studio",destination:URL(string:"https://aistudio.google.com/apikey")!)
                }
                Section("Credenciales de este Mac") {
                    SecureField(model.ui(model.googleKeySaved ? "Reemplazar clave API":"Clave API de Google AI"),text:$googleKey).accessibilityIdentifier("googleAPIKey")
                    HStack {
                        Button("Guardar en el Llavero") { let value=googleKey; Task { if await model.saveGoogleKey(value) { googleKey="" } } }.disabled(googleKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        Button("Eliminar clave",role:.destructive) { Task { await model.deleteGoogleKey() } }.disabled(!model.googleKeySaved)
                    }
                    Text(model.ui(model.googleKeySaved ? "Hay una clave guardada en el Llavero. No se incluye en sesiones ni exportaciones.":"Todavía no hay una clave guardada.")).font(.caption).foregroundStyle(.secondary)
                }
                Section("Modelo y conexión") {
                    TextField("Modelo",text:Binding(get:{model.settings.googleModel ?? GoogleAIClient.defaultModel},set:{model.settings.googleModel=$0})).accessibilityIdentifier("googleModel")
                    HStack {
                        Button("Probar conexión") { Task { await model.testGoogleConnection() } }.disabled(model.settings.googleEnabled != true || !model.googleKeySaved || model.googleTesting)
                        if model.googleTesting { ProgressView().controlSize(.small) }
                        Button("Aplicar a la sesión seleccionada") { Task { await model.setSessionGoogle(true) } }.disabled(model.settings.googleEnabled != true || model.selectedSession==nil || model.active || model.summaryWorking)
                    }
                    Text(model.ui(model.googleStatus)).font(.caption).textSelection(.enabled)
                    Text("Probar conexión consulta el modelo sin enviar transcripciones. Actualizar resumen aplica los cambios al contenido de la sesión.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Google AI",systemImage:"cloud") }
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
                    Text("Las descargas requieren autorización. Apple Intelligence se configura desde Ajustes del Sistema. Google AI solo usa red cuando se activa explícitamente.").font(.caption).foregroundStyle(.secondary)
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
            Form {
                Section("Idioma de la interfaz") {
                    Picker("Idioma",selection:Binding(get:{model.settings.interfaceLanguage ?? .spanish},set:{model.settings.interfaceLanguage=$0})) {
                        ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                    }.accessibilityIdentifier("interfaceLanguage")
                    Text("No cambia el idioma de transcripción ni traduce las sesiones guardadas.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Paleta de la aplicación") {
                    Text("Elige un acento. Los fondos y el texto siguen la apariencia clara u oscura de macOS.").font(.callout).foregroundStyle(.secondary)
                    PalettePicker(selection:Binding(get:{model.settings.colorPalette ?? .petroleum},set:{model.settings.colorPalette=$0}))
                    Text("Captura, avisos y errores conservan sus colores de estado.").font(.caption).foregroundStyle(.secondary)
                }
                Section("PAIMON") {
                    HStack(spacing:16) {
                        Image(nsImage:NSApplication.shared.applicationIconImage).resizable().frame(width:64,height:64).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:5) {
                            Text("Local Audio Intelligence").font(.headline)
                            Text("Transformando sonido en conocimiento.").foregroundStyle(.secondary)
                            Text("Versión \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Desarrollo")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Creado por Sebastián Pastén F.").textSelection(.enabled)
                    Link(destination:URL(string:"https://ko-fi.com/C0C51WQ1T0")!) {
                        Label("Apoyar el desarrollo en Ko-fi",systemImage:"cup.and.saucer.fill")
                    }.help("Abrir Ko-fi en tu navegador").accessibilityIdentifier("supportKoFi")
                    Text("Tu aporte es voluntario y ayuda a mantener el proyecto.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Apariencia",systemImage:"paintpalette") }
        }.padding(12).frame(width:720,height:640)
            .modifier(AppTheme(palette:model.settings.colorPalette ?? .petroleum,language:model.settings.interfaceLanguage ?? .spanish)).onDisappear { googleKey="" }
    }
    private func pathRow(_ title:String,key:WritableKeyPath<AppSettings,String>,folder:Bool) -> some View {
        HStack { TextField(LocalizedStringKey(title),text:Binding(get:{model.settings[keyPath:key]},set:{model.settings[keyPath:key]=$0})); Button("Elegir…") { model.choosePath(key,folder:folder) } }
    }
}

struct AppTheme:ViewModifier {
    var palette:AppPalette
    var language:AppLanguage = .spanish
    @Environment(\.colorScheme) private var scheme
    func body(content:Content) -> some View { content.tint(palette.tint(for:scheme)).environment(\.locale,language.locale) }
}
extension AppModel {
    /// Dynamic UI strings require explicit lookup; session content is never passed here.
    func ui(_ key:String) -> String {
        guard settings.interfaceLanguage == .english,
              let path=Bundle.main.path(forResource:"en",ofType:"lproj"),let bundle=Bundle(path:path) else { return key }
        let translated=bundle.localizedString(forKey:key,value:key,table:nil)
        if translated != key { return translated }
        for prefix in ["Resumen pendiente: ","Síntesis pendiente: ","Generando resumen · ","Resumen actualizado · "] where key.hasPrefix(prefix) {
            return bundle.localizedString(forKey:prefix,value:prefix,table:nil)+key.dropFirst(prefix.count)
        }
        return key
    }
}
extension AppPalette {
    func tint(for scheme:ColorScheme) -> Color {
        let light:(Double,Double,Double),dark:(Double,Double,Double)
        switch self {
        case .petroleum: light=(0.13,0.36,0.45); dark=(0.40,0.72,0.82)
        case .sage: light=(0.26,0.40,0.30); dark=(0.62,0.77,0.62)
        case .copper: light=(0.60,0.29,0.17); dark=(0.91,0.64,0.46)
        case .graphite: light=(0.31,0.35,0.40); dark=(0.73,0.77,0.83)
        }
        let value=scheme == .dark ? dark:light
        return Color(red:value.0,green:value.1,blue:value.2)
    }
}
private struct PalettePicker:View {
    @Binding var selection:AppPalette
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        HStack(spacing:10) {
            ForEach(AppPalette.allCases) { palette in
                Button { selection=palette } label: {
                    VStack(spacing:10) {
                        HStack(spacing:5) {
                            Circle().fill(palette.tint(for:scheme)).frame(width:25,height:25)
                            Circle().fill(palette.tint(for:scheme).opacity(0.35)).frame(width:16,height:16)
                        }.frame(height:30)
                        Text(LocalizedStringKey(palette.title)).font(.callout.weight(.medium))
                        Image(systemName:selection==palette ? "checkmark.circle.fill":"circle").foregroundStyle(selection==palette ? palette.tint(for:scheme):Color.secondary)
                    }.frame(maxWidth:.infinity).padding(.vertical,14)
                        .background(palette.tint(for:scheme).opacity(selection==palette ? 0.10:0.03),in:RoundedRectangle(cornerRadius:10))
                        .overlay { RoundedRectangle(cornerRadius:10).strokeBorder(selection==palette ? palette.tint(for:scheme):Color.secondary.opacity(0.2),lineWidth:selection==palette ? 2:1) }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Paleta \(palette.title)")
                    .accessibilityAddTraits(selection==palette ? .isSelected:[])
                    .accessibilityIdentifier("palette-\(palette.rawValue)")
            }
        }.padding(.vertical,6)
    }
}
