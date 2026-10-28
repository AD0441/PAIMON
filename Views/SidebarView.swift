import SwiftUI
import AppKit
import LAICore
struct SidebarView:View {
    @Bindable var model:AppModel
    @State private var deleting:Session?
    @FocusState private var searchFocused:Bool
    var body:some View {
        VStack(spacing:0) {
            HStack { Text("Sesiones").font(.headline); Spacer(); Button { model.newSession() } label: { Image(systemName:"plus") }.help("Nueva sesión").disabled(model.active) }.padding(16)
            Picker("Buscar en",selection:$model.globalSearchMode) { Text("Sesiones").tag(false); Text("Transcripciones").tag(true) }.pickerStyle(.segmented).labelsHidden().padding(.horizontal,12).padding(.bottom,10)
            if model.globalSearchMode {
                TextField("Buscar en todas las transcripciones",text:$model.globalQuery).textFieldStyle(.roundedBorder).focused($searchFocused).padding(.horizontal,12).padding(.bottom,10)
                    .accessibilityIdentifier("globalTranscriptSearch")
                if model.searching { ProgressView().controlSize(.small).padding(6) }
                if model.indexingSearch { Text(model.ui(model.active ? "Índice del historial en espera durante la captura.":"Preparando el índice del historial…")).font(.caption).foregroundStyle(.secondary).padding(.horizontal,12) }
                if let error=model.searchError { Text(error).font(.caption).foregroundStyle(.secondary).padding(12) }
                List {
                    ForEach(model.searchHits) { hit in
                        Button { Task { await model.openSearchHit(hit) } } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text(hit.title).fontWeight(.medium).lineLimit(1)
                                Text("\(hit.created.formatted(date:.abbreviated,time:.omitted)) · \(timestamp(hit.start)) · \(hit.source.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(hit.snippet).font(.caption).lineLimit(3).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("searchHit-\(hit.id)")
                    }
                }.listStyle(.sidebar).frame(minHeight:0,maxHeight:.infinity)
                if !model.searching { Text(model.globalQuery.count<2 ? "Escribe al menos dos caracteres.":model.searchHits.isEmpty ? "Sin coincidencias.":"\(model.searchHits.count) resultados · máximo 50").font(.caption2).foregroundStyle(.secondary).padding(10) }
            } else {
            TextField("Buscar sesiones",text:$model.sessionSearch).textFieldStyle(.roundedBorder).padding(.horizontal,12).padding(.bottom,10)
            List(selection:Binding(get:{model.selected},set:{value in Task { await model.select(value) }})) {
                ForEach(model.sessions) { session in
                    Label {
                        VStack(alignment:.leading,spacing:4) {
                            Text(session.title).lineLimit(1)
                            Text("\(session.created.formatted(date:.abbreviated,time:.shortened)) · \(timestamp(session.duration))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } icon: { Image(systemName:session.status=="recording" ? "waveform":"text.alignleft") }
                    .tag(session.id)
                    .contextMenu { Button("Eliminar sesión…",role:.destructive) { deleting=session }.disabled(model.current?.id==session.id && model.active) }
                }
            }.listStyle(.sidebar).frame(minHeight:0,maxHeight:.infinity)
            if model.historyPage>0 || model.moreSessions {
                HStack {
                    Button { Task { await model.refreshSessions(page:model.historyPage-1) } } label: { Image(systemName:"chevron.left") }.disabled(model.historyPage==0)
                    Text("Página \(model.historyPage+1)").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await model.refreshSessions(page:model.historyPage+1) } } label: { Image(systemName:"chevron.right") }.disabled(!model.moreSessions)
                }.padding(8)
            }
            }
            Divider()
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:10) {
                    Image(nsImage:SidebarView.symbol).renderingMode(.template).resizable().scaledToFit()
                        .frame(width:34,height:34).accessibilityHidden(true)
                    Text("PAIMON").font(.headline)
                }.foregroundStyle(.tint)
                Label("Audio en tu Mac",systemImage:"lock.shield").font(.callout).foregroundStyle(.secondary)
                SettingsLink { Label("Ajustes",systemImage:"gearshape") }
                    .buttonStyle(.plain).font(.body).help("Configuración").accessibilityIdentifier("sidebarSettings")
                Text("Creado por Sebastián Pastén F.").font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(16).fixedSize(horizontal:false,vertical:true)
        }
        .task(id:model.globalQuery+String(model.globalSearchMode)+String(model.indexingSearch)) { await model.searchAllTranscripts() }
        .onChange(of:model.globalSearchMode) { _,value in if value { searchFocused=true } }
        .onChange(of:model.globalSearchFocus) { _,_ in searchFocused=true }
        .task(id:model.sessionSearch) {
            do { try await Task.sleep(for:.milliseconds(300)); try Task.checkCancellation(); await model.refreshSessions() } catch {}
        }
        .alert("¿Eliminar la sesión?",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting=nil }})) {
            Button("Cancelar",role:.cancel) { deleting=nil }
            Button("Eliminar",role:.destructive) { if let session=deleting { Task { await model.delete(session) } }; deleting=nil }
        } message: { Text("Se eliminarán la transcripción, los resúmenes y cualquier audio guardado de esta sesión.") }
    }
    private static let symbol:NSImage = {
        guard let url=Bundle.main.url(forResource:"PAIMON-symbol",withExtension:"png"),let image=NSImage(contentsOf:url) else { return NSImage() }
        image.isTemplate=true; return image
    }()
}
