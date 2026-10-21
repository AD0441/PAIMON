import SwiftUI
import LAICore
struct TranscriptView:View {
    @Bindable var model:AppModel
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Label("Transcripción",systemImage:"text.bubble").font(.headline); Spacer()
                Button { Task { await model.addBookmark() } } label: { Label("Marcar",systemImage:"bookmark") }.controlSize(.small).disabled(!model.canAddBookmark).help("Marcar este momento · ⌘⇧M").accessibilityIdentifier("addBookmark")
                Toggle("Seguir",isOn:$model.autoScroll).toggleStyle(.checkbox).font(.caption)
            }.padding(16)
            TextField("Buscar palabras en la sesión",text:Binding(get:{model.transcriptSearch},set:{ value in
                model.transcriptSearch=value
                Task { await model.select(model.selected) }
            })).textFieldStyle(.roundedBorder).padding(.horizontal,16).padding(.bottom,12)
            if !model.terms.isEmpty {
                VStack(alignment:.leading,spacing:5) {
                    Text("Términos frecuentes · muestra de esta vista").font(.caption2).foregroundStyle(.secondary).help("Hasta 300 fragmentos y 100.000 caracteres; frecuencia, no importancia semántica")
                    ScrollView(.horizontal) {
                        HStack(spacing:6) {
                            ForEach(model.terms) { term in
                                Button("\(term.text) · \(term.count)") {
                                    model.transcriptSearch=term.text
                                    Task { await model.select(model.selected) }
                                }.buttonStyle(.bordered).controlSize(.mini).help("Buscar este término en la sesión")
                            }
                        }
                    }.scrollIndicators(.hidden)
                }.padding(.horizontal,16).padding(.bottom,10)
            }
            DisclosureGroup(isExpanded:$model.showBookmarks) {
                if model.bookmarks.isEmpty { Text("Sin marcadores en esta página.").font(.caption).foregroundStyle(.secondary).padding(8) }
                else {
                    ScrollView {
                        LazyVStack(spacing:10) { ForEach(model.bookmarks) { bookmark in BookmarkRow(bookmark:bookmark,model:model) } }.padding(.vertical,6)
                    }.frame(height:min(220,CGFloat(model.bookmarks.count)*88))
                }
                HStack {
                    if model.bookmarkPage>0 { Button("Anteriores") { Task { await model.loadBookmarks(page:model.bookmarkPage-1) } } }
                    Spacer()
                    if model.moreBookmarks { Button("Siguientes") { Task { await model.loadBookmarks(page:model.bookmarkPage+1) } } }
                }.font(.caption)
            } label: { Label("Marcadores y notas",systemImage:"bookmark").font(.caption.weight(.medium)) }.padding(.horizontal,16).padding(.bottom,10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:20) {
                        if model.segments.isEmpty && model.partials.isEmpty {
                            ContentUnavailableView(model.active ? "Escuchando…":"Listo para escuchar",systemImage:"waveform",description:Text(model.active ? "El texto aparecerá al reconocer voz.":"Reproduce audio, elige una fuente y pulsa Iniciar.")).frame(maxWidth:.infinity,minHeight:300)
                        }
                        ForEach(model.segments) { segment in segmentView(segment).id(segment.id) }
                        ForEach(model.partials.values.sorted{$0.start<$1.start}) { segment in segmentView(segment).opacity(0.6) }
                        Color.clear.frame(height:1).id("end")
                    }.padding(20)
                }
                .onChange(of:model.segments.count) { _,_ in if model.autoScroll { proxy.scrollTo("end",anchor:.bottom) } }
                .onChange(of:model.partials) { _,_ in if model.autoScroll { proxy.scrollTo("end",anchor:.bottom) } }
                .onChange(of:model.evidenceNavigation) { _,_ in
                    if let id=model.transcriptTarget { proxy.scrollTo(id,anchor:.center) }
                }
            }
            HStack {
                if model.canLoadEarlier { Button("Anteriores") { Task { await model.loadEarlier() } } }
                Button("Más recientes") { Task { await model.select(model.selected); model.autoScroll=true } }.disabled(model.selected==nil)
                Spacer()
            }.font(.caption).padding(.horizontal,16).padding(.top,8)
            Text("Vista paginada de 300 fragmentos. Exporta para obtener el documento completo.").font(.caption2).foregroundStyle(.secondary).padding(10)
        }
    }
    private func segmentView(_ segment:TranscriptSegment) -> some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:8) {
                Text(timestamp(segment.start)).monospacedDigit()
                Text(segment.source.title)
                if !segment.isFinal { Text("Parcial") }
                if segment.duplicateOf != nil { Text("Posible eco") }
                Spacer()
                Button { model.copy(segment.text) } label: { Image(systemName:"doc.on.doc") }.buttonStyle(.plain).help("Copiar fragmento")
            }.font(.caption).foregroundStyle(.secondary)
            Text(segment.text).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(8).background(model.transcriptTarget==segment.id ? Color.accentColor.opacity(0.1):Color.clear,in:RoundedRectangle(cornerRadius:8))
        .contextMenu {
            Button("Copiar fragmento") { model.copy("[\(timestamp(segment.start))] \(segment.text)") }
            Button("Marcar este fragmento") { Task { await model.addBookmark(time:segment.start,segmentID:segment.id) } }.disabled(!segment.isFinal)
        }
    }
}
private struct BookmarkRow:View {
    var bookmark:SessionBookmark
    var model:AppModel
    @State private var note:String
    @State private var deleting=false
    init(bookmark:SessionBookmark,model:AppModel) { self.bookmark=bookmark; self.model=model; _note=State(initialValue:bookmark.note) }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Button { Task { await model.openBookmark(bookmark) } } label: { Label(timestamp(bookmark.time),systemImage:"bookmark.fill").monospacedDigit() }.buttonStyle(.plain).help("Ir al momento marcado")
                Spacer()
                if note != bookmark.note { Button("Guardar") { Task { await model.updateBookmark(bookmark,note:note) } }.controlSize(.small) }
                Button(role:.destructive) { deleting=true } label: { Image(systemName:"trash") }.buttonStyle(.plain).help("Eliminar marcador")
            }.font(.caption)
            TextField("Añadir nota…",text:$note,axis:.vertical).lineLimit(1...3).textFieldStyle(.roundedBorder).font(.caption)
                .onSubmit { Task { await model.updateBookmark(bookmark,note:note) } }
                .onChange(of:note) { _,value in if value.count>2000 { note=String(value.prefix(2000)) } }
        }
        .onChange(of:bookmark.note) { _,value in note=value }
        .confirmationDialog("¿Eliminar este marcador y su nota?",isPresented:$deleting) {
            Button("Eliminar marcador",role:.destructive) { Task { await model.deleteBookmark(bookmark) } }
            Button("Cancelar",role:.cancel) {}
        }
    }
}
