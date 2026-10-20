import SwiftUI
import LAICore
struct ExportSheet:View {
    var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var format:ExportFormat = .markdown
    @State private var options=ExportOptions()
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Exportar sesión").font(.title2.weight(.semibold))
            Picker("Formato",selection:$format) { ForEach(ExportFormat.allCases,id:\.self) { Text($0.rawValue.uppercased()).tag($0) } }.pickerStyle(.segmented)
            Toggle("Transcripción completa",isOn:$options.transcript)
            Toggle("Marcadores y notas",isOn:$options.bookmarks)
            Toggle("Anexo de evidencias",isOn:$options.evidence).disabled(format == .json)
            Text(format == .json ? "JSON conserva las citas y referencias estructuradas.":"Las citas van en un anexo. PDF y Markdown incluyen enlaces desde el resumen.").font(.caption).foregroundStyle(.secondary)
            ForEach(FindingKind.allCases,id:\.self) { kind in
                Toggle(kind.title,isOn:Binding(get:{options.kinds.contains(kind)},set:{if $0 { options.kinds.insert(kind) } else { options.kinds.remove(kind) }}))
            }
            HStack { Spacer(); Button("Cancelar") { dismiss() }; Button("Exportar…") { dismiss(); Task { await model.export(format:format,options:options) } }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width:400)
    }
}
