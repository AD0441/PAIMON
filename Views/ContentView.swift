import SwiftUI
import LAICore
struct ContentView:View {
    @Bindable var model:AppModel
    var body:some View {
        // Bound both columns to the size proposed by NavigationSplitView.
        // Their intrinsic content heights must not enlarge the window layout.
        NavigationSplitView(columnVisibility:$model.sidebarVisibility) {
            GeometryReader { area in
                SidebarView(model:model).frame(width:area.size.width,height:area.size.height)
            }.navigationSplitViewColumnWidth(min:220,ideal:255,max:340)
        } detail: {
            GeometryReader { area in
                VStack(spacing:0) {
                    CaptureHeader(model:model).layoutPriority(1)
                    Divider()
                    if let message=model.message {
                        HStack(alignment:.top) {
                            Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(message).font(.callout).textSelection(.enabled)
                            Spacer(); Button { model.message=nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain)
                        }.padding(12).background(.orange.opacity(0.08))
                        Divider()
                    }
                    SessionPanes(model:model).frame(minHeight:0,maxHeight:.infinity)
                    Divider()
                    HStack(spacing:16) {
                        Label(model.ui(model.settings.googleEnabled==true ? "Audio local · Google AI opcional":"Procesamiento local"),systemImage:model.settings.googleEnabled==true ? "cloud":"lock.shield").foregroundStyle(.secondary)
                        if model.active,model.pendingSummarySegments>0 { Text("\(model.pendingSummarySegments) fragmentos por resumir").foregroundStyle(.secondary) }
                        Spacer()
                        if model.pressure { Label("Memoria bajo presión",systemImage:"memorychip").foregroundStyle(.orange) }
                        ResourceStatus(model:model)
                        Text(model.ui(model.settings.saveAudio ? "Audio guardado":"Audio sin guardar")).foregroundStyle(.secondary)
                    }.font(.caption).padding(.horizontal,18).padding(.vertical,9).fixedSize(horizontal:false,vertical:true)
                }.frame(width:area.size.width,height:area.size.height,alignment:.top)
            }
            .navigationTitle(model.selectedSession?.title ?? "PAIMON")
            .toolbar(removing:.title)
            .toolbarBackgroundVisibility(.visible,for:.windowToolbar)
            .toolbar {
                ToolbarItem(placement:.primaryAction) { Button { model.showExport=true } label: { Label("Exportar",systemImage:"square.and.arrow.up") }.disabled(model.selectedSession==nil) }
                ToolbarItem(placement:.primaryAction) { SettingsLink { Image(systemName:"slider.horizontal.3") }.help("Configuración") }
            }
        }.modifier(AppTheme(palette:model.settings.colorPalette ?? .petroleum,language:model.settings.interfaceLanguage ?? .spanish))
            .sheet(isPresented:$model.showExport) { ExportSheet(model:model) }
            .dropDestination(for:URL.self) { urls,_ in
                guard !model.active,let url=urls.first else { return false }
                model.beginImport(url); return true
            }
    }
}

private struct ResourceStatus:View {
    var model:AppModel
    var body:some View {
        Text("\(model.metrics.footprintMB,specifier:"%.0f") MB").monospacedDigit().foregroundStyle(.secondary)
            .help("Memoria del proceso; no incluye los servicios de modelos de Apple. Se actualiza cada cinco segundos con la ventana abierta.")
            .task {
                while !Task.isCancelled {
                    if !model.active { model.metrics=ResourceMetrics.current() }
                    do { try await Task.sleep(for:.seconds(5)) } catch { return }
                }
            }
    }
}

/// A bounded workspace with a persistent divider; resizing never changes the
/// amount of vertical space reserved for capture controls and the footer.
private struct SessionPanes:View {
    var model:AppModel
    @SceneStorage("sessionTranscriptFraction") private var fraction=0.55
    @State private var dragStart:CGFloat?
    var body:some View {
        GeometryReader { available in
            let width=max(0,available.size.width-9)
            let lower=min(width,max(340,width-550))
            let upper=max(lower,width-300)
            let transcript=min(upper,max(lower,width*fraction))
            HStack(spacing:0) {
                TranscriptView(model:model).frame(width:transcript,height:available.size.height).clipped()
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width:1)
                    .frame(width:9,height:available.size.height).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.global).onChanged { value in
                        if dragStart==nil { dragStart=transcript }
                        fraction=min(upper,max(lower,(dragStart ?? transcript)+value.translation.width))/max(1,width)
                    }.onEnded { _ in dragStart=nil })
                    .accessibilityElement().accessibilityLabel("Divisor entre transcripción y resumen")
                    .accessibilityValue("\(Int(transcript/max(1,width)*100)) por ciento para transcripción")
                    .accessibilityAdjustableAction { direction in
                        let change:CGFloat=direction == .increment ? 32:-32
                        fraction=min(upper,max(lower,transcript+change))/max(1,width)
                    }
                    .help("Arrastra para ajustar el ancho de los paneles")
                SummaryView(model:model).frame(width:max(0,width-transcript),height:available.size.height).clipped()
            }.frame(width:available.size.width,height:available.size.height)
        }
    }
}
