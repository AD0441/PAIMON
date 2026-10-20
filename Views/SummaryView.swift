import SwiftUI
import LAICore
struct SummaryView:View {
    @Bindable var model:AppModel
    @State private var copied=false
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Label("Resumen",systemImage:"sparkles").font(.headline)
                Spacer()
                Button { Task { copied=await model.copySessionReport() } } label: { Label(copied ? "Copiado":"Copiar texto",systemImage:copied ? "checkmark":"doc.on.doc") }
                    .accessibilityIdentifier("copySessionReport")
                    .disabled(model.findings.isEmpty || model.selectedSession==nil)
                    .help("Copiar el informe con formato para Word o Pages")
                if model.summaryWorking { ProgressView().controlSize(.small) }
                Button { Task { await model.updateSummary(final:!model.active) } } label: { Image(systemName:"arrow.clockwise") }.buttonStyle(.plain).help("Actualizar resumen").disabled(model.summaryWorking || model.selectedSession==nil || model.pressure)
                    .contextMenu {
                        Button("Rehacer desde la transcripción") { Task { await model.updateSummary(final:!model.active,rebuild:true) } }
                    }
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Text(model.summaryStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let report=model.report,!report.sections.isEmpty {
                        VStack(alignment:.leading,spacing:6) {
                            Text(report.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                            Text(report.metadata).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(report.sections) { section in
                            VStack(alignment:.leading,spacing:12) {
                                Text(section.kind.title).font(.headline)
                                if section.kind == .tasks { taskTable(section.items) }
                                else {
                                    ForEach(section.items) { item in
                                        HStack(alignment:.bottom,spacing:8) {
                                            HStack(alignment:.firstTextBaseline,spacing:8) {
                                                if section.kind != .overview { Text("•").foregroundStyle(.secondary) }
                                                Text(styled(item.finding.text,emphasis:section.kind != .overview))
                                                    .lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                            }
                                            evidence(item)
                                        }
                                    }
                                }
                            }
                        }
                        Text("Cada icono de cita permite revisar el fragmento original.").font(.caption2).foregroundStyle(.secondary)
                        if model.findingPage>0 || model.moreFindings {
                            HStack {
                                Button("Anteriores") { Task { await model.loadFindings(page:model.findingPage-1) } }.disabled(model.findingPage==0)
                                Text("Hallazgos · página \(model.findingPage+1)").font(.caption).foregroundStyle(.secondary)
                                Button("Siguientes") { Task { await model.loadFindings(page:model.findingPage+1) } }.disabled(!model.moreFindings)
                            }
                            Text("Copiar y exportar incluyen el registro completo de esta sesión.").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("Las ideas toman forma",systemImage:"text.badge.star",description:Text("El resumen se actualiza cada \(Int(model.settings.summaryInterval/60)) minutos con citas de la transcripción.")).frame(maxWidth:.infinity,minHeight:220)
                    }
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
        .onChange(of:model.findings) { _,_ in copied=false }
        .onChange(of:model.title) { _,_ in copied=false }
        .onChange(of:model.selected) { _,_ in copied=false }
    }
    private func styled(_ text:String,emphasis:Bool) -> AttributedString {
        var result=AttributedString(text)
        if emphasis {
            let prefix=SessionReportFormatter.emphasizedPrefix(in:text)
            if let range=result.range(of:prefix) { result[range].font = .body.bold() }
        }
        return result
    }
    private func evidence(_ item:ReportItem) -> some View {
        EvidenceButton(item:item) { id in Task { await model.revealTranscriptSegment(id) } }
    }
    private func taskTable(_ items:[ReportItem]) -> some View {
        Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:12) {
            GridRow {
                Text("Tarea").frame(maxWidth:.infinity,alignment:.leading)
                Text("Responsable")
                Text("Fecha")
                Color.clear.frame(width:16,height:1)
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellColumns(4).gridCellUnsizedAxes(.horizontal)
            ForEach(items) { item in
                GridRow(alignment:.top) {
                    Text(item.finding.text).frame(maxWidth:.infinity,alignment:.leading)
                    Text(item.owner)
                    Text(item.due)
                    evidence(item)
                }.font(.callout).textSelection(.enabled)
                Divider().gridCellColumns(4).gridCellUnsizedAxes(.horizontal)
            }
        }
    }
}
private struct EvidenceButton:View {
    var item:ReportItem
    var reveal:(String)->Void
    @State private var shown=false
    var body:some View {
        Button { shown=true } label: { Image(systemName:"quote.bubble").font(.caption).foregroundStyle(.secondary) }
            .buttonStyle(.plain).help("Ver evidencia · \(timestamp(item.finding.start))")
            .accessibilityLabel("Ver evidencia")
            .accessibilityIdentifier("evidence-\(item.reference)")
            .popover(isPresented:$shown) {
                VStack(alignment:.leading,spacing:12) {
                    Label("Evidencia",systemImage:"quote.bubble").font(.headline)
                    ScrollView {
                        VStack(alignment:.leading,spacing:16) {
                            ForEach(Array(item.sources.enumerated()),id:\.offset) { _,source in
                                VStack(alignment:.leading,spacing:8) {
                                    Text("\(source.sourceTitle) · \(timestamp(source.start)) - \(timestamp(source.end))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                    Text("«\(source.quote)»").textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).lineSpacing(4)
                                    Button("Ir al fragmento") { shown=false; reveal(source.segmentID) }
                                }
                            }
                        }
                    }.frame(height:item.sources.count>1 ? 300:200)
                }.padding(18).frame(width:320)
            }
    }
}
