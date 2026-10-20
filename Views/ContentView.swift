import SwiftUI
import LAICore
struct ContentView:View {
    @Bindable var model:AppModel
    var body:some View {
        NavigationSplitView(columnVisibility:$model.sidebarVisibility) {
            SidebarView(model:model).navigationSplitViewColumnWidth(min:220,ideal:255,max:340)
        } detail: {
            VStack(spacing:0) {
                CaptureHeader(model:model)
                Divider()
                if let message=model.message {
                    HStack(alignment:.top) {
                        Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer(); Button { model.message=nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain)
                    }.padding(12).background(.orange.opacity(0.08))
                    Divider()
                }
                HSplitView {
                    TranscriptView(model:model).frame(minWidth:340)
                    SummaryView(model:model).frame(minWidth:300,idealWidth:390,maxWidth:550)
                }
                Divider()
                HStack(spacing:16) {
                    Label("Procesamiento local",systemImage:"lock.shield").foregroundStyle(.secondary)
                    if model.active,model.pendingSummarySegments>0 { Text("\(model.pendingSummarySegments) fragmentos por resumir").foregroundStyle(.secondary) }
                    Spacer()
                    if model.pressure { Label("Memoria bajo presión",systemImage:"memorychip").foregroundStyle(.orange) }
                    Text("\(model.metrics.footprintMB,specifier:"%.0f") MB").monospacedDigit().foregroundStyle(.secondary)
                    Text(model.settings.saveAudio ? "Audio guardado":"Audio sin guardar").foregroundStyle(.secondary)
                }.font(.caption).padding(.horizontal,18).padding(.vertical,9)
                Text("Creado con desprecio por Sebastián Pastén F.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled).padding(.bottom,8)
            }
            .navigationTitle(model.selectedSession?.title ?? "PAIMON")
            .toolbar {
                ToolbarItem { Button { model.showExport=true } label: { Label("Exportar",systemImage:"square.and.arrow.up") }.disabled(model.selectedSession==nil) }
                ToolbarItem { SettingsLink { Image(systemName:"slider.horizontal.3") }.help("Configuración") }
            }
        }.sheet(isPresented:$model.showExport) { ExportSheet(model:model) }
    }
}
