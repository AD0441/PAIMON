import SwiftUI
import LAICore

struct ExportSheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .markdown
    @State private var options = ExportOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exportar sesión").font(.title2.weight(.semibold))
            Picker("Formato", selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Transcripción completa", isOn: $options.transcript)
                    if options.transcript { Toggle("Exportar texto original sin correcciones", isOn: $options.originalTranscript) }
                    Toggle("Marcadores y notas", isOn: $options.bookmarks)
                    Divider()
                    Text("Análisis").font(.headline)
                    Toggle("Sentimientos y datos vocales", isOn: $options.sentiments)
                    Toggle("Discurso y participación", isOn: $options.discourse)
                    Toggle("Asistente: consultas, respuestas y citas", isOn: $options.assistant)
                    Text("Solo se exportan resultados ya calculados. Exportar no ejecuta IA.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Resumen").font(.headline)
                    if model.processingProgress.summaryNeedsRefresh {
                        Text("Actualiza el resumen para incluir las correcciones.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(FindingKind.allCases, id: \.self) { kind in
                            Toggle(model.ui(kind.title), isOn: Binding(get: { options.kinds.contains(kind) }, set: {
                                if $0 { options.kinds.insert(kind) } else { options.kinds.remove(kind) }
                            }))
                        }
                    }
                    Divider()
                    if format != .json { Toggle("Anexo de evidencias", isOn: $options.evidence) }
                    Text(model.ui(format == .json ? "JSON conserva las citas y referencias estructuradas." :
                        "Las citas van en un anexo. PDF y Markdown incluyen enlaces desde el resumen."))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Exportar…") {
                    var selection = options
                    if model.processingProgress.summaryNeedsRefresh { selection.kinds = [] }
                    dismiss()
                    Task { await model.export(format: format, options: selection) }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:480,height:640)
    }
}
