import SwiftUI
import Observation
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import LAICore
@MainActor @Observable
final class AppModel {
    @ObservationIgnored private let preferences:UserDefaults
    @ObservationIgnored private let summaryEngineOverride:(@MainActor (Session?) -> any SummarizationEngine)?
    @ObservationIgnored private let pressureRetryInterval:Duration
    var settings:AppSettings { didSet { settings.save(to:preferences) } }
    var state:CaptureState = .idle {
        didSet {
            if !active && summaryRecoveryRequested { resumePendingSummaries() }
        }
    }
    var sessions:[Session]=[]
    var historyPage=0
    var moreSessions=false
    private var selectedRecord:Session?
    let importedPlayback = ImportedAudioPlayback()
    var selected:UUID? {
        didSet {
            if selected != oldValue {
                importedPlayback.stop()
                speakerTask?.cancel()
                speakerLabels=[:]
                findings=[]
                findingPage=0
                moreFindings=false
                hasSummaryToCopy=false
            }
            if let selected { preferences.set(selected.uuidString,forKey:"lastSelectedSession") }
            else { preferences.removeObject(forKey:"lastSelectedSession") }
        }
    }
    var current:Session?
    var title="Nueva sesión"
    var segments:[TranscriptSegment]=[] { didSet { refreshSpeakers() } }
    private(set) var speakerLabels:[String:SessionSpeaker]=[:]
    @ObservationIgnored private var speakerTask:Task<Void,Never>?
    var diarizationEnabled:Bool {
        get { settings.diarizationEnabled==true }
        set { settings.diarizationEnabled=newValue }
    }
    var partials:[AudioSource:TranscriptSegment]=[:]
    var findings:[Finding]=[]
    var reportPresentation:ReportPresentation = .complete
    private var loadedFindingKinds:[FindingKind]=[]
    @ObservationIgnored private var findingsRequest=UUID()
    private(set) var hasSummaryToCopy=false
    var reportLoading:Bool { loadedFindingKinds != reportPresentation.registerKinds }
    var findingPage=0
    var moreFindings=false
    var pendingSummarySegments=0
    var sessionSearch=""
    var globalSearchMode=false
    var sidebarVisibility:NavigationSplitViewVisibility = .automatic
    var globalSearchFocus=UUID()
    var globalQuery=""
    var searchHits:[TranscriptSearchHit]=[]
    var searching=false
    var indexingSearch=true
    var searchError:String?
    var bookmarks:[SessionBookmark]=[]
    var bookmarkPage=0
    var moreBookmarks=false
    var showBookmarks=false
    var transcriptSearch=""
    var oldestRow:Int64=0
    var canLoadEarlier=false
    var autoScroll=true
    var transcriptTarget:String?
    var evidenceNavigation=UUID()
    var elapsed:Double=0
    var reportDuration:Double=0
    var levels:[AudioSource:Float]=[:]
    var voice:[AudioSource:Bool]=[:]
    var message:String?
    var speechStatus="Comprobando motor…"
    var capturePreparation:CapturePreparation = .checkingVoice
    var summaryStatus="Comprobando modelo…"
    var summaryAvailability="Comprobando modelo…"
    var summaryWorking=false
    var googleRetryStatus:String?
    var sessionContext=SessionContext()
    var processingProgress=SessionProcessingProgress()
    var terms:[SessionTerm]=[]
    var importFraction:Double=0
    var importDuration:Double=0
    var googleKeySaved=false
    var googleStatus="Google AI desactivado"
    var googleTesting=false
    var metrics=ResourceMetrics.current()
    var pressure=false
    var showExport=false
    var store:SessionStore?
    private var pipeline:RecordingPipeline?
    private var coordinator:SummaryCoordinator?
    private var eventTask:Task<Void,Never>?
    private var clockTask:Task<Void,Never>?
    private var summaryTask:Task<Void,Never>?
    private var summaryRequests=0
    @ObservationIgnored private let googleClient:GoogleAIClient
    private var importTask:Task<Void,Never>?
    private var progressTask:Task<Void,Never>?
    private var termsTask:Task<Void,Never>?
    private var finalRecoveryTask:Task<Void,Never>?
    private var pressureRecoveryTask:Task<Void,Never>?
    @ObservationIgnored private var pressureInterruptions = 0
    @ObservationIgnored private var summaryRecoveryRequested = false
    @ObservationIgnored private var displayBuffer=LiveDisplayBuffer()
    @ObservationIgnored private var displayTask:Task<Void,Never>?
    private var indexTask:Task<Void,Never>?
    private var searchRequest=UUID()
    private var selectionRequest=UUID()
    private var historyRequest=UUID()
    private var memorySource:(any DispatchSourceMemoryPressure)?
    private var started:Double=0
    private var lastSummary:Double=0
    private var ready=false
    var validationStarted=false
    #if DEBUG
    var validationTask:Task<Void,Never>?
    #endif
    var active:Bool { [.preparing,.recording,.paused,.stopping,.importing].contains(state) }
    var recordingSession:Bool { current?.id==selected && active }
    var canAddBookmark:Bool { selectedSession != nil && state != .preparing && state != .stopping }
    var selectedSession:Session? { (current?.id==selected ? current:nil) ?? sessions.first{$0.id==selected} ?? (selectedRecord?.id==selected ? selectedRecord:nil) }
    var canStartAudio:Bool { !active && !summaryWorking && finalRecoveryTask==nil }
    var canEditTranscript:Bool { !active && !summaryWorking && finalRecoveryTask==nil }
    var waitingForMemoryRecovery:Bool { pressureRecoveryTask != nil }
    var canUpdateSummary:Bool {
        selectedSession != nil && !summaryWorking && !pressure && finalRecoveryTask==nil &&
        ![.preparing,.importing,.stopping].contains(state)
    }
    var statusTitle:String {
        switch state {
        case .idle:
            if processingProgress.transcribedThrough>0 {
                selectedSession?.status=="interrupted" ? "Transcripción parcial guardada":"Transcripción lista"
            } else { "Listo" }
        case .preparing: capturePreparation.title
        case .recording: "Capturando"
        case .paused: "En pausa"
        case .stopping: "Guardando transcripción"
        case .importing: "Importando audio"
        case .failed: "Requiere atención"
        }
    }
    init(store suppliedStore:SessionStore?=nil,preferences:UserDefaults = .standard,googleClient:GoogleAIClient=GoogleAIClient(),summaryEngine:(@MainActor (Session?) -> any SummarizationEngine)?=nil,pressureRetryInterval:Duration = .seconds(15)) {
        self.preferences=preferences; settings=AppSettings.load(from:preferences)
        self.googleClient=googleClient; summaryEngineOverride=summaryEngine
        self.pressureRetryInterval=pressureRetryInterval
        do { let value=try suppliedStore ?? SessionStore(); store=value; pipeline=RecordingPipeline(store:value); coordinator=SummaryCoordinator(store:value) }
        catch { message=error.localizedDescription }
    }
    func bootstrap() async {
        guard !ready else { return }; ready=true
        do { try await store?.recoverInterrupted(); await refreshSessions()
            let saved=preferences.string(forKey:"lastSelectedSession").flatMap(UUID.init(uuidString:))
            if let id=saved ?? sessions.first?.id { await select(id) } } catch { message=error.localizedDescription }
        await googleClient.setEnabled(settings.googleEnabled==true)
        googleKeySaved=(try? await googleClient.hasKey()) ?? false
        googleStatus=settings.googleEnabled==true ? (googleKeySaved ? "Clave disponible en el Llavero; conexión sin comprobar.":"Google AI activado; falta guardar una clave."):"Google AI desactivado; procesamiento local."
        await checkAvailability()
        let source=DispatchSource.makeMemoryPressureSource(eventMask:[.normal,.warning,.critical],queue:.main)
        source.setEventHandler { @Sendable [weak self,weak source] in
            guard let events=source?.data else { return }
            MainActor.assumeIsolated {
                if events.contains(.warning) || events.contains(.critical) { self?.memoryPressureChanged(true) }
                else if events.contains(.normal) { self?.memoryPressureChanged(false) }
            }
        }
        source.resume(); memorySource=source
        if (try? await store?.pendingFinalSession()) != nil {
            summaryRecoveryRequested = true
            resumePendingSummaries()
        }
        if let store {
            indexTask=Task(priority:.utility) { @concurrent [weak self,store] in
                do {
                    while !Task.isCancelled {
                        guard let allowed=await self?.mayIndexHistory else { break }
                        if !allowed { try await Task.sleep(for:.seconds(1)); continue }
                        let factsDone=try await store.indexNextFindingBatch()
                        let done=try await store.indexNextSearchBatch()
                        if done && factsDone { await self?.finishedSearchIndex(error:nil); break }
                        try await Task.sleep(for:.milliseconds(50))
                    }
                } catch is CancellationError {} catch { await self?.finishedSearchIndex(error:error.localizedDescription) }
            }
        }
    }
    private var mayIndexHistory:Bool { !pressure && !active }
    func memoryPressureChanged(_ value:Bool) {
        guard pressure != value else { return }
        pressure=value
        if value {
            pressureRecoveryTask?.cancel()
            pressureRecoveryTask=nil
            if summaryWorking { pressureInterruptions=min(4,pressureInterruptions+1) }
            Task { await coordinator?.cancelAll() }
        } else {
            summaryRecoveryRequested = true
            let interval=pressureRetryInterval * (1 << max(0,pressureInterruptions-1))
            pressureRecoveryTask=Task { @concurrent [weak self] in
                do { try await Task.sleep(for:interval) } catch { return }
                await self?.memoryPressureSettled()
            }
        }
    }
    private func memoryPressureSettled() {
        guard !Task.isCancelled else { return }
        pressureRecoveryTask=nil
        resumePendingSummaries()
    }
    private func resumePendingSummaries() {
        guard summaryRecoveryRequested,finalRecoveryTask==nil,pressureRecoveryTask==nil,
              !active,!pressure,!summaryWorking else { return }
        summaryRecoveryRequested = false
        finalRecoveryTask=Task { [weak self] in
            guard let self else { return }
            defer {
                self.finalRecoveryTask=nil
                self.resumePendingSummaries()
            }
            await self.summaryTask?.value
            do {
                guard !self.active,!self.pressure else { return }
                let jobs=try await self.store?.pendingFinalSessions() ?? []
                for session in jobs {
                    guard !self.active,!self.pressure else { break }
                    // Each job gets one attempt. An unavailable provider on an
                    // older session must not block newer saved transcripts.
                    await self.updateSummary(final:true,for:session)
                }
                if try await self.store?.pendingFinalSession()==nil,!self.pressure { self.pressureInterruptions=0 }
            } catch { self.summaryStatus="Síntesis pendiente: \(error.localizedDescription)" }
        }
    }
    private func finishedSearchIndex(error:String?) { indexingSearch=false; searchError=error }
    func captureDiagnostics() async -> CaptureDiagnostics { await pipeline?.captureDiagnostics() ?? CaptureDiagnostics() }
    func checkAvailability() async {
        speechStatus=await AppleSpeechEngine.availability(locale:settings.locale,refresh:true) ?? "SpeechTranscriber · recursos instalados"
        let session=selectedSession,request=selectionRequest
        let engine=makeSummaryEngine(template:session?.template ?? selectedTemplate,session:session)
        let reason=await engine.availability(locale:session?.settings.locale ?? settings.locale)
        if request==selectionRequest { summaryAvailability=reason ?? "\(summaryProviderTitle) · disponible" }
        await engine.unload()
    }
    private func makeSummaryEngine(template:SummaryTemplate = .meeting,session:Session?=nil) -> any SummarizationEngine {
        if let summaryEngineOverride { return summaryEngineOverride(session) }
        let value=session?.settings ?? settings.forNewSession()
        let context=session?.context ?? sessionContext
        let backend=value.summaryBackend(googleAllowed:settings.googleEnabled==true)
        switch backend {
        case .apple: return FoundationSummaryEngine(template:template,context:context)
        case .mlx: return MLXSummaryEngine(settings:settings,template:template,context:context)
        case .google: return GoogleSummaryEngine(client:googleClient,model:value.googleModel ?? GoogleAIClient.defaultModel,template:template,context:context)
        }
    }
    var selectedUsesGoogle:Bool {
        if let session=selectedSession { return session.settings.googleSummarySelected==true }
        return settings.googleEnabled==true
    }
    var summaryProviderTitle:String {
        let value=selectedSession?.settings ?? settings.forNewSession()
        return value.summaryBackend(googleAllowed:settings.googleEnabled==true).title
    }
    func setGoogleEnabled(_ value:Bool) async {
        settings.googleEnabled=value
        await googleClient.setEnabled(value)
        if !value { await coordinator?.cancelAll() }
        googleStatus=value ? "Solo las sesiones que seleccionen Google AI enviarán texto.":"Google AI desactivado; procesamiento local."
        await checkAvailability()
    }
    func saveGoogleKey(_ value:String) async -> Bool {
        do { try await googleClient.saveKey(value); googleKeySaved=true; googleStatus="Clave guardada en el Llavero de este Mac."; return true }
        catch { googleStatus=error.localizedDescription; return false }
    }
    func deleteGoogleKey() async {
        do { try await googleClient.deleteKey(); googleKeySaved=false; googleStatus="Clave eliminada del Llavero." }
        catch { googleStatus=error.localizedDescription }
    }
    func testGoogleConnection() async {
        guard !googleTesting else { return }; googleTesting=true; defer { googleTesting=false }
        do { let name=try await googleClient.testConnection(model:settings.googleModel ?? GoogleAIClient.defaultModel); googleStatus="Conexión comprobada: \(name). No se envió ninguna transcripción." }
        catch { googleStatus=error.localizedDescription }
    }
    func setSessionGoogle(_ value:Bool) async {
        guard !active,!summaryWorking else { return }
        if value && settings.googleEnabled != true { return }
        guard var session=selectedSession else { return }
        session.settings.googleSummarySelected=value
        if !value { session.settings.summary=settings.summary == .mlx ? .mlx:.apple }
        session.settings.googleModel=settings.googleModel
        do {
            guard try await store?.updateExistingSession(session)==true else { return }
            selectedRecord=session; if current?.id==session.id { current=session }
            await refreshSessions()
            summaryStatus="Motor cambiado a \(session.settings.summaryBackend(googleAllowed:settings.googleEnabled==true).title). Pulsa Actualizar resumen para aplicarlo a esta sesión."
        } catch { message=error.localizedDescription }
    }
    func saveSessionContext() async {
        guard !active,!summaryWorking else { return }
        sessionContext=sessionContext.bounded
        guard var session=selectedSession else { return }
        session.context=sessionContext
        do {
            guard try await store?.updateExistingSession(session)==true else { return }
            selectedRecord=session
            if current?.id==session.id { current=session }
            await refreshSessions(); summaryStatus="Contexto guardado. Pulsa Actualizar resumen para aplicarlo."
        } catch { message=error.localizedDescription }
    }
    func refreshProcessingProgress() async {
        googleRetryStatus=await googleClient.retryStatus
        guard let id=selected else { processingProgress = .init(); return }
        let request=selectionRequest
        do { let value=try await store?.processingProgress(session:id) ?? .init(); if selected==id,selectionRequest==request { processingProgress=value } }
        catch { message=error.localizedDescription }
    }
    func refreshSpeakers() {
        speakerTask?.cancel()
        guard let session=selectedSession,session.settings.diarizationEnabled==true,
              !segments.isEmpty,let store else {
            if !speakerLabels.isEmpty { speakerLabels=[:] }
            return
        }
        let values=segments
        speakerTask=Task { [weak self] in
            do {
                try await Task.sleep(for:.milliseconds(250))
                let labels=try await store.speakers(for:values,session:session.id)
                try Task.checkCancellation()
                if self?.selected==session.id { self?.speakerLabels=labels }
            } catch is CancellationError {
            } catch {
                if self?.selected==session.id { self?.message=error.localizedDescription }
            }
        }
    }
    func renameSpeaker(_ speaker:SessionSpeaker,session:UUID,name:String) async -> Bool {
        guard let store,selected==session else { return false }
        do {
            try await store.renameSpeaker(session:session,id:speaker.id,name:name)
            if selected==session { refreshSpeakers() }
            return true
        } catch {
            message=error.localizedDescription
            return false
        }
    }
    func refreshTerms() {
        termsTask?.cancel()
        let values=segments,id=selected
        termsTask=Task { @concurrent [weak self] in
            do { try await Task.sleep(for:.milliseconds(500)); try Task.checkCancellation() } catch { return }
            let ranked=SessionTerm.rank(values)
            guard !Task.isCancelled else { return }
            await MainActor.run { if self?.selected==id { self?.terms=ranked } }
        }
    }
    var selectedTemplate:SummaryTemplate { selectedSession?.template ?? settings.summaryTemplate ?? .meeting }
    func setSummaryTemplate(_ template:SummaryTemplate) async {
        guard !active,!summaryWorking else { return }
        settings.summaryTemplate=template
        guard var session=selectedSession,session.template != template else { return }
        session.summaryTemplate=template
        do {
            guard try await store?.updateExistingSession(session)==true else { return }
            if current?.id==session.id { current=session }
            await refreshSessions()
            if selected==session.id { summaryStatus="Plantilla cambiada a \(template.title). Pulsa Actualizar resumen para aplicarla al contenido anterior." }
        } catch { message=error.localizedDescription }
    }
    func searchAllTranscripts() async {
        let request=UUID(); searchRequest=request
        let query=globalQuery
        guard globalSearchMode,query.trimmingCharacters(in:.whitespacesAndNewlines).count>=2 else { searchHits=[]; searching=false; searchError=nil; return }
        searching=true; searchHits=[]
        defer { if searchRequest==request { searching=false } }
        do {
            try await Task.sleep(for:.milliseconds(300)); try Task.checkCancellation()
            let values=try await store?.searchTranscripts(query) ?? []
            try Task.checkCancellation()
            guard globalQuery==query,globalSearchMode,searchRequest==request else { return }
            searchHits=values; searchError=nil
        } catch is CancellationError {} catch { if globalQuery==query { searchError=error.localizedDescription } }
    }
    func beginGlobalSearch() { sidebarVisibility = .all; globalSearchMode=true; globalSearchFocus=UUID() }
    func openSearchHit(_ hit:TranscriptSearchHit) async {
        sessionSearch=""; transcriptSearch=""; await refreshSessions()
        await select(hit.sessionID)
        guard selected==hit.sessionID else { return }
        await revealTranscriptSegment(hit.segmentID)
    }
    func refreshSessions(page:Int=0) async {
        let query=sessionSearch,request=UUID(); historyRequest=request
        do {
            let values=try await store?.sessions(search:query,limit:50,offset:max(0,page)*50) ?? []
            guard query==sessionSearch,historyRequest==request else { return }
            sessions=values; historyPage=max(0,page); moreSessions=values.count==50
        } catch { message=error.localizedDescription }
    }
    func select(_ id:UUID?) async {
        let request=UUID(); selectionRequest=request
        selected=id; selectedRecord=nil; displayBuffer=LiveDisplayBuffer(); partials=[:]; segments=[]; findings=[]; findingPage=0; moreFindings=false; transcriptTarget=nil; bookmarks=[]; bookmarkPage=0; moreBookmarks=false
        termsTask?.cancel(); terms=[]; processingProgress = .init(); sessionContext = .init(); oldestRow=0; canLoadEarlier=false
        summaryStatus="El resumen aparecerá cuando haya texto definitivo."
        guard let id else { return }
        if let session=selectedSession { title=session.title }
        let query=transcriptSearch
        do {
            let record=try await store?.session(id:id)
            guard selected==id,selectionRequest==request else { return }
            selectedRecord=record; if let record { title=record.title; sessionContext=record.context ?? .init() }
            let rows=try await store?.segments(session:id,limit:300,search:query,newest:true) ?? []
            guard selected==id,selectionRequest==request,transcriptSearch==query else { return }
            segments=rows.map(\.1).sorted{$0.start<$1.start}; oldestRow=rows.first?.0 ?? 0; canLoadEarlier=rows.count==300
            refreshTerms(); await refreshProcessingProgress()
            let snapshot=try await store?.latestSummary(session:id)
            let markers=try await store?.bookmarks(session:id) ?? []
            guard selected==id,selectionRequest==request,transcriptSearch==query else { return }
            await loadFindings()
            guard selected==id,selectionRequest==request else { return }
            bookmarks=markers; moreBookmarks=markers.count==100
            if let snapshot,!snapshot.findings.contains(where:{$0.kind == .overview}) || (settings.summary == .apple && (snapshot.processingVersion ?? 0)<2) {
                summaryStatus="Este resumen anterior necesita reconstruirse. Pulsa Actualizar resumen para procesar la transcripción completa."
            } else if processingProgress.summaryNeedsRefresh {
                summaryStatus="Actualiza el resumen para incluir las correcciones."
            } else if processingProgress.finalQueued {
                summaryStatus=queuedSummaryStatus
            } else if let snapshot { summaryStatus=snapshot.isFinal ? "Síntesis final guardada":"Resumen parcial guardado" }
        } catch { if selectionRequest==request { message=error.localizedDescription } }
    }
    func filterTranscript() async {
        guard let id=selected else { return }
        let query=transcriptSearch,request=selectionRequest
        // Clearing the field while following evidence must keep its source window.
        guard !query.isEmpty || transcriptTarget==nil else { return }
        do {
            try await Task.sleep(for:.milliseconds(250)); try Task.checkCancellation()
            let rows=try await store?.segments(session:id,limit:300,search:query,newest:true) ?? []
            try Task.checkCancellation()
            guard selected==id,selectionRequest==request,transcriptSearch==query else { return }
            transcriptTarget=nil; segments=rows.map(\.1).sorted{$0.start<$1.start}
            oldestRow=rows.first?.0 ?? 0; canLoadEarlier=rows.count==300; refreshTerms()
        } catch is CancellationError {} catch { if selectionRequest==request { message=error.localizedDescription } }
    }
    func loadFindings(page:Int=0) async {
        guard let session=selectedSession,let store else { return }
        let selection=selectionRequest
        let request=UUID()
        let kinds=reportPresentation.registerKinds
        let page=max(0,page)
        let pageSize=120
        findingsRequest=request
        do {
            // Historical import yields between small transactions; audio writes
            // use this same actor and can interleave with migration work.
            while try await !store.indexNextFindingBatch(session:session.id) { try Task.checkCancellation(); await Task.yield() }
            let values=try await store.reportFindings(session:session.id,template:session.template,
                                                      kinds:kinds,limit:pageSize+1,offset:page*pageSize)
            var hasSummary = !values.isEmpty
            if !hasSummary,(!kinds.isEmpty || page>0) {
                hasSummary = try await !store.findings(session:session.id,template:session.template,limit:1).isEmpty
            }
            guard selected==session.id,selectionRequest==selection,findingsRequest==request,reportPresentation.registerKinds==kinds else { return }
            moreFindings=values.filter{$0.kind != .overview && $0.kind != .topic}.count>pageSize
            findings=moreFindings ? Array(values.dropLast()):values
            findingPage=page
            hasSummaryToCopy=hasSummary
            loadedFindingKinds=kinds
        } catch is CancellationError {
            return
        } catch {
            guard selected==session.id,selectionRequest==selection,findingsRequest==request,reportPresentation.registerKinds==kinds else { return }
            findings=[]; findingPage=0; moreFindings=false
            loadedFindingKinds=kinds
            message=error.localizedDescription
        }
    }
    func revealEvidence(_ finding:Finding) async {
        await revealTranscriptSegment(finding.segmentID)
    }
    func revealTranscriptSegment(_ segmentID:String) async {
        guard let id=selected,let store else { return }
        let request=selectionRequest
        do {
            let rows=try await store.segmentWindow(session:id,segmentID:segmentID)
            let earlier=try await store.segments(session:id,limit:1,before:rows.first?.0 ?? 0)
            guard selected==id,selectionRequest==request else { return }
            guard !rows.isEmpty else { message="El fragmento original no está disponible en esta sesión."; return }
            autoScroll=false; transcriptSearch=""
            segments=rows.map(\.1).sorted{$0.start<$1.start}
            refreshTerms()
            oldestRow=rows.first?.0 ?? 0; canLoadEarlier = !earlier.isEmpty
            transcriptTarget=segmentID; evidenceNavigation=UUID()
        } catch { message=error.localizedDescription }
    }
    func loadBookmarks(page:Int=0) async {
        guard let id=selected else { bookmarks=[]; return }
        do {
            let values=try await store?.bookmarks(session:id,offset:max(0,page)*100) ?? []
            guard selected==id else { return }
            bookmarkPage=max(0,page); bookmarks=values; moreBookmarks=values.count==100
        } catch { message=error.localizedDescription }
    }
    func addBookmark(time:Double?=nil,segmentID:String?=nil,capture:Bool=false) async {
        guard state != .preparing,state != .stopping else { return }
        guard let session=capture && active ? current:selectedSession else { return }
        let position=time ?? ((capture && active) || recordingSession ? elapsed:segments.first{$0.id==transcriptTarget}?.start ?? session.duration)
        let bookmark=SessionBookmark(sessionID:session.id,time:position,segmentID:segmentID)
        do {
            try await store?.save(bookmark)
            if selected==session.id {
                let page=try await store?.bookmarkPage(containing:bookmark) ?? 0
                showBookmarks=true; await loadBookmarks(page:page)
            }
        } catch { message=error.localizedDescription }
    }
    func updateBookmark(_ bookmark:SessionBookmark,note:String) async {
        var value=bookmark; value.note=String(note.prefix(2000))
        do { try await store?.save(value); if selected==bookmark.sessionID { await loadBookmarks(page:bookmarkPage) } }
        catch { message=error.localizedDescription }
    }
    func deleteBookmark(_ bookmark:SessionBookmark) async {
        do { try await store?.deleteBookmark(bookmark.id); if selected==bookmark.sessionID { await loadBookmarks(page:bookmarkPage) } }
        catch { message=error.localizedDescription }
    }
    func openBookmark(_ bookmark:SessionBookmark) async {
        guard selected==bookmark.sessionID else { return }
        do {
            let target:String?
            if let known=bookmark.segmentID { target=known }
            else { target=try await store?.segmentID(session:bookmark.sessionID,at:bookmark.time) }
            if let id=target { await revealTranscriptSegment(id) }
            else { message="El marcador está guardado. Todavía no hay texto definitivo en ese momento." }
        } catch { message=error.localizedDescription }
    }
    func loadEarlier() async {
        guard let id=selected else { return }
        do {
            let rows=try await store?.segments(session:id,limit:300,search:transcriptSearch,newest:true,before:oldestRow) ?? []
            guard selected==id else { return }
            segments=rows.map(\.1).sorted{$0.start<$1.start}; oldestRow=rows.first?.0 ?? 0; canLoadEarlier=rows.count==300; autoScroll=false
            refreshTerms()
        } catch { message=error.localizedDescription }
    }
    func start() async {
        guard canStartAudio,let pipeline else { return }
        importedPlayback.stop()
        capturePreparation = .checkingVoice
        state = .preparing; message=nil; findings=[]; findingPage=0; moreFindings=false; displayBuffer=LiveDisplayBuffer(); segments=[]; partials=[:]; bookmarks=[]; bookmarkPage=0; moreBookmarks=false
        do {
            let (session,events)=try await pipeline.start(title:title,settings:settings.forNewSession(),context:sessionContext.bounded) { [weak self] stage in
                await self?.showCapturePreparation(stage)
            }
            current=session; selected=session.id; sessions.insert(session,at:0)
            started=ProcessInfo.processInfo.systemUptime; elapsed=0; reportDuration=0; lastSummary=0; state = .recording
            eventTask=Task { [weak self] in
                for await event in events {
                    guard let self else { break }
                    switch event {
                    case .segment(let segment):
                        if segment.isFinal {
                            if self.selected==segment.sessionID {
                                self.displayBuffer.finalized(segment.source); self.partials[segment.source]=nil
                                if let i=self.segments.firstIndex(where:{$0.id==segment.id}) { self.segments[i]=segment } else { self.segments.append(segment) }
                                self.segments.sort{$0.start<$1.start}; if self.segments.count>300 { self.segments.removeFirst(self.segments.count-300) }
                                self.refreshTerms()
                            }
                        } else if self.selected==segment.sessionID { self.displayBuffer.partial(segment); self.scheduleDisplayFlush() }
                    case .activity(let source,let level,let active):
                        if self.state == .recording { self.displayBuffer.activity(source,level:level,active:active); self.scheduleDisplayFlush() }
                    case .speakersUpdated(let id):
                        if self.selected==id { self.refreshSpeakers() }
                    case .warning(let text): self.message=text
                    case .failure(let text): self.message=text; Task { await self.stop() }
                    }
                }
            }
            clockTask=Task { @concurrent [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for:.seconds(1)) } catch { break }
                    await self?.tick()
                }
            }
        } catch { state = .failed; message=error.localizedDescription; await refreshSessions() }
    }
    private func showCapturePreparation(_ stage:CapturePreparation) {
        if state == .preparing { capturePreparation=stage }
    }
    func openPrivacySettings() {
        if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.systempreferences") {
            NSWorkspace.shared.open(url)
        }
    }
    func chooseAudioFile() {
        guard canStartAudio else { return }
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.audio]; panel.allowsMultipleSelection=false
        panel.message="Importar una grabación para transcribirla en este Mac."
        if panel.runModal() == .OK,let url=panel.url { beginImport(url) }
    }
    func beginImport(_ url:URL) {
        guard canStartAudio,let store else { return }
        importedPlayback.stop()
        guard url.isFileURL else { message="Selecciona un archivo de audio local."; return }
        let title=url.deletingPathExtension().lastPathComponent
        var session=Session(title:title,settings:settings.forNewSession()); session.context=sessionContext.bounded; session.importedFileName=url.lastPathComponent; session.status="importing"
        current=session; selected=session.id; selectedRecord=session; self.title=title
        selectionRequest=UUID(); displayBuffer=LiveDisplayBuffer(); transcriptSearch=""; transcriptTarget=nil; oldestRow=0; canLoadEarlier=false
        segments=[]; partials=[:]; findings=[]; terms=[]; findingPage=0; moreFindings=false; bookmarks=[]; bookmarkPage=0; moreBookmarks=false
        summaryStatus="El resumen aparecerá cuando haya texto definitivo."
        state = .importing; message=nil; importFraction=0; importDuration=0; elapsed=0; reportDuration=0; processingProgress = .init()
        let value=session
        importTask=Task { @concurrent [weak self,store] in
            let scoped=url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(128))
            let display=Task { @MainActor [weak self] in
                for await event in pair.stream {
                    guard let self else { break }
                    if case .segment(let segment)=event,self.selected==segment.sessionID {
                        if segment.isFinal {
                            self.partials[.file]=nil
                            if let index=self.segments.firstIndex(where:{$0.id==segment.id}) { self.segments[index]=segment } else { self.segments.append(segment) }
                            self.segments.sort{$0.start<$1.start}
                            if self.segments.count>300 { self.segments.removeFirst(self.segments.count-300) }
                            self.refreshTerms()
                        } else { self.partials[.file]=segment }
                    } else if case .speakersUpdated(let id)=event,self.selected==id {
                        self.refreshSpeakers()
                    } else if case .warning(let warning)=event {
                        self.message=warning
                    }
                }
            }
            do {
                let completed=try await AudioFileTranscriber.importSession(url:url,session:value,store:store,events:pair.continuation,progress:{ [weak self] seconds,total in await self?.importProgress(seconds:seconds,total:total) })
                if let bookmark=try? ImportedAudioPlayback.bookmark(for:url) {
                    try? await store.saveAudioBookmark(bookmark,session:completed.id)
                }
                await display.value
                await self?.finishImport(completed,error:nil,cancelled:false)
            } catch {
                await display.value
                let saved=(try? await store.session(id:value.id)) ?? value
                await self?.finishImport(saved,error:error.localizedDescription,cancelled:error is CancellationError)
            }
        }
    }
    private func importProgress(seconds:Double,total:Double) async {
        guard state == .importing else { return }
        elapsed=seconds; importDuration=total; importFraction=total>0 ? min(1,seconds/total):0
        await refreshProcessingProgress()
    }
    private func finishImport(_ session:Session,error:String?,cancelled:Bool) async {
        current=session; reportDuration=session.duration; partials=[:]; state = .stopping
        if let error { message=cancelled ? "Importación cancelada. Los fragmentos reconocidos permanecen guardados.":error }
        await refreshSessions()
        if selected==session.id { await select(session.id) }
        importTask=nil
        await finishTranscript(session,requestSummary:error==nil)
    }
    private var queuedSummaryStatus:String {
        pressure ? "Síntesis en espera hasta que baje la presión de memoria.":"Resumen pendiente de generación."
    }
    func finishTranscript(_ session:Session,requestSummary:Bool) async {
        if requestSummary {
            do {
                try await store?.requestFinalSummary(session:session.id)
                summaryRecoveryRequested = true
                if selected==session.id { summaryStatus=queuedSummaryStatus }
            } catch {
                message=error.localizedDescription
            }
        }
        await refreshProcessingProgress()
        state = .idle
    }
    func waitForSummaryRecovery() async {
        await pressureRecoveryTask?.value
        await finalRecoveryTask?.value
    }
    func cancelImport() { importTask?.cancel() }
    func stopActiveWork() async {
        if state == .importing { importTask?.cancel(); await importTask?.value }
        else { await stop() }
    }
    private func scheduleDisplayFlush() {
        guard displayTask==nil else { return }
        displayTask=Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(300)) } catch { return }
            guard let self else { return }
            let values=self.displayBuffer.drain()
            for (source,segment) in values.partials where segment.sessionID==self.selected { self.partials[source]=segment }
            for (source,level) in values.levels { self.levels[source]=level }
            for (source,active) in values.voice { self.voice[source]=active }
            self.displayTask=nil
        }
    }
    private func tick() async {
        elapsed=ProcessInfo.processInfo.systemUptime-started
        if Int(elapsed)%30==0 { reportDuration=elapsed }
        if Int(elapsed)%5==0 { metrics=ResourceMetrics.current(); try? await pipeline?.checkpoint() }
        if Int(elapsed)%5==0,let id=current?.id {
            await refreshProcessingProgress()
            let cursor=try? await store?.latestSummary(session:id)?.throughRow
            let pending=(try? await store?.pendingContent(session:id,after:cursor ?? 0)) ?? .init()
            pendingSummarySegments=pending.segments
            if state == .recording,!summaryWorking,SummarySchedule.shouldUpdate(pending:pending,secondsSinceUpdate:elapsed-lastSummary,interval:settings.summaryInterval,underPressure:pressure || (settings.energySaving && metrics.thermal>=2)) {
                lastSummary=elapsed; summaryTask=Task { await updateSummary(final:false) }
            }
        }
    }
    func pauseOrResume() async {
        if state == .recording {
            await pipeline?.pause(); state = .paused
            displayTask?.cancel(); displayTask=nil; displayBuffer=LiveDisplayBuffer(); voice=[:]; levels=[:]
        }
        else if state == .paused {
            do { try await pipeline?.resume(); state = .recording } catch { message=error.localizedDescription }
        }
    }
    func stop() async {
        guard [.recording,.paused].contains(state) else { return }
        state = .stopping; clockTask?.cancel(); clockTask=nil
        do {
            if let value=try await pipeline?.stop() { current=value; reportDuration=value.duration }
            await eventTask?.value; eventTask=nil
            displayTask?.cancel(); displayTask=nil; displayBuffer=LiveDisplayBuffer(); partials=[:]; voice=[:]
            await refreshSessions()
            if let current { await finishTranscript(current,requestSummary:true) }
            else { state = .idle }
        } catch {
            eventTask?.cancel(); await eventTask?.value; eventTask=nil
            if let id=current?.id,let saved=try? await store?.session(id:id) {
                current=saved; reportDuration=saved.duration
                try? await store?.requestFinalSummary(session:id)
            }
            displayTask?.cancel(); displayTask=nil; displayBuffer=LiveDisplayBuffer(); partials=[:]; voice=[:]
            message=error.localizedDescription; state = .failed; await refreshSessions()
        }
    }
    func updateSummary(final:Bool,rebuild:Bool=false,for sessionOverride:Session?=nil) async {
        guard let session=sessionOverride ?? (active ? current:selectedSession),let coordinator else { return }
        summaryRequests += 1; summaryWorking=true
        if progressTask==nil {
            progressTask=Task { @concurrent [weak self] in
                while !Task.isCancelled {
                    await self?.refreshProcessingProgress()
                    do { try await Task.sleep(for:.seconds(2)) } catch { break }
                }
            }
        }
        defer {
            summaryRequests -= 1; summaryWorking=summaryRequests>0
            if !summaryWorking {
                progressTask?.cancel(); progressTask=nil; googleRetryStatus=nil
                resumePendingSummaries()
            }
        }
        do {
            if final,!rebuild,sessionOverride==nil {
                try await store?.requestFinalSummary(session:session.id)
                await refreshProcessingProgress()
            }
            try Task.checkCancellation()
            guard !pressure else {
                if selected==session.id { summaryStatus=queuedSummaryStatus }
                return
            }
        } catch is CancellationError {
            return
        } catch {
            if selected==session.id { summaryStatus="Resumen pendiente: \(error.localizedDescription)" }
            return
        }
        if selected==session.id { summaryStatus=rebuild ? "Reconstruyendo desde la transcripción original…":"Generando resumen · \(summaryProviderTitle)…" }
        let engine=makeSummaryEngine(template:session.template,session:session)
        do {
            let reason=await engine.availability(locale:session.settings.locale)
            try Task.checkCancellation()
            guard !pressure else { throw CancellationError() }
            if let reason {
                if selected==session.id { summaryStatus=reason }
                await engine.unload(); return
            }
            _=try await coordinator.update(session:session,engine:engine,final:final,rebuild:rebuild)
            if selected==session.id { await loadFindings(page:reportLoading ? 0:findingPage) }
            if selected==session.id { summaryStatus = !hasSummaryToCopy ? "No hay hallazgos con evidencia todavía":final ? "Síntesis final actualizada":"Resumen actualizado · \(Date().formatted(date:.omitted,time:.shortened))" }
            if final { try await store?.completeFinalSummary(session:session.id) }
            await refreshProcessingProgress()
        } catch is CancellationError { if selected==session.id { summaryStatus="Resumen en espera; la transcripción permanece guardada." } }
        catch { if selected==session.id { summaryStatus="Resumen pendiente: \(error.localizedDescription)" } }
        await engine.unload()
    }
    func newSession() { guard !active else { return }; selectionRequest=UUID(); selected=nil; selectedRecord=nil; title="Nueva sesión"; segments=[]; findings=[]; findingPage=0; moreFindings=false; partials=[:]; bookmarks=[]; bookmarkPage=0; transcriptTarget=nil; moreBookmarks=false; showBookmarks=false; transcriptSearch=""; oldestRow=0; canLoadEarlier=false; sessionContext = .init(); processingProgress = .init(); termsTask?.cancel(); terms=[]; message=nil; googleRetryStatus=nil; summaryStatus="El resumen aparecerá cuando haya texto definitivo." }
    func delete(_ session:Session) async {
        guard (current?.id != session.id || !active),let store else { return }
        do {
            await coordinator?.cancel(session:session.id)
            try await store.delete(session:session.id)
            if current?.id==session.id { current=nil }
            searchRequest=UUID()
            searching=false
            searchHits.removeAll { $0.sessionID==session.id }
            if selected==session.id {
                if active { await select(current?.id) }
                else { newSession() }
            }
            await refreshSessions()
            if globalSearchMode { await searchAllTranscripts() }
        } catch { message=error.localizedDescription }
    }
    func rename() async {
        guard var session=selectedSession else { return }
        session.title=title
        do {
            guard try await store?.updateExistingSession(session)==true else { return }
            if current?.id==session.id { current=session }
            await refreshSessions()
        } catch { message=error.localizedDescription }
    }
    func installSpeech() async {
        speechStatus="Descargando recursos de voz autorizados…"
        do { try await AppleSpeechEngine.install(locale:settings.locale); await checkAvailability() } catch { speechStatus=error.localizedDescription }
    }
    var report:SessionReport? {
        guard !reportLoading,var session=selectedSession else { return nil }
        if recordingSession { session.duration=reportDuration }
        return SessionReportFormatter.document(session:session,findings:reportPresentation.select(findings),
                                               deduplicate:reportPresentation != .followUp)
    }
    @discardableResult func copySessionReport() async -> Bool {
        guard let session=selectedSession,let store else { return false }
        var all:[Finding]=[]
        do {
            let revision=try await store.transcriptRevision(session:session.id)
            guard !(try await store.summaryNeedsRefresh(session:session.id)) else { return false }
            let memory=try await store.latestSummary(session:session.id)?.findings.filter{$0.kind == .topic || $0.kind == .overview} ?? []
            all=memory; var offset=0
            while true {
                let page=try await store.findings(session:session.id,template:session.template,limit:200,offset:offset)
                if page.isEmpty { break }; all += page; offset += page.count
            }
            guard revision==(try await store.transcriptRevision(session:session.id)) else { return false }
        } catch { message=error.localizedDescription; return false }
        let report=SessionReportFormatter.document(session:session,findings:all)
        let plain=SessionReportFormatter.plainText(report)
        let styled=SessionReportFormatter.richText(report)
        let full=NSRange(location:0,length:styled.length)
        do {
            let item=NSPasteboardItem()
            item.setString(plain,forType:.string)
            item.setData(try styled.data(from:full,documentAttributes:[.documentType:NSAttributedString.DocumentType.rtf]),forType:.rtf)
            item.setData(Data(SessionReportFormatter.html(report).utf8),forType:.html)
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([item])
        } catch { message="No se pudo copiar el informe con formato: \(error.localizedDescription)"; return false }
    }
    func copy(_ text:String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string) }
    func correctTranscript(_ segment:TranscriptSegment,text:String) async -> Bool {
        guard canEditTranscript,selected==segment.sessionID,let store else { return false }
        do {
            let corrected=try await store.correctSegment(session:segment.sessionID,id:segment.id,text:text)
            if selected==segment.sessionID {
                if let index=segments.firstIndex(where:{$0.id==segment.id}) { segments[index]=corrected }
                refreshTerms()
                await refreshProcessingProgress()
                if selected==segment.sessionID,processingProgress.summaryNeedsRefresh {
                    summaryStatus="Actualiza el resumen para incluir las correcciones."
                }
            }
            return true
        } catch {
            message=error.localizedDescription
            return false
        }
    }
    private func chooseOriginalAudio(for session:Session) async throws -> URL? {
        let picker=NSOpenPanel()
        picker.allowedContentTypes=[.audio]
        picker.allowsMultipleSelection=false
        picker.prompt=ui("Vincular")
        picker.message=ui("Selecciona el archivo original de esta sesión.")
        guard picker.runModal() == .OK,let url=picker.url else { return nil }
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let duration=try await AVURLAsset(url:url).load(.duration).seconds
        guard duration.isFinite,duration>0,
              session.status != "completed" || abs(duration-session.duration)<=2 else {
            throw LAIError.message("La duración del archivo no coincide con la sesión.")
        }
        guard selected==session.id,!active,let store else { return nil }
        try await store.saveAudioBookmark(ImportedAudioPlayback.bookmark(for:url),session:session.id)
        return url
    }
    func linkOriginalAudio() async {
        guard !active,let session=selectedSession,session.importedFileName != nil else { return }
        do { _=try await chooseOriginalAudio(for:session) }
        catch { message=error.localizedDescription }
    }
    func playOriginalAudio(start:Double,end:Double) async {
        guard !active,let session=selectedSession,session.importedFileName != nil,let store else { return }
        do {
            let bookmark=try await store.audioBookmark(session:session.id)
            guard selected==session.id,!active else { return }
            let linked=bookmark.flatMap { try? ImportedAudioPlayback.resolve($0) }
            let url:URL?
            if let linked { url=linked }
            else { url=try await chooseOriginalAudio(for:session) }
            guard selected==session.id,!active,let url else { return }
            try await importedPlayback.play(url,start:start,end:end)
        } catch { message=error.localizedDescription }
    }
    func copyTranscript() async {
        guard let session=selectedSession,let store else { return }
        do {
            var text=""
            var cursor:Int64=0
            while true {
                let page=try await store.segments(session:session.id,after:cursor,limit:200)
                guard let last=page.last else { break }
                for (_,segment) in page {
                    text += "[\(timestamp(segment.start))] \(segment.text)\n"
                }
                cursor=last.0
            }
            if !text.isEmpty { copy(text) }
        } catch { message=error.localizedDescription }
    }
    func choosePath(_ key:WritableKeyPath<AppSettings,String>,folder:Bool) {
        if let path=choosePath(folder:folder) { settings[keyPath:key]=path }
    }
    func choosePath(folder:Bool) -> String? {
        let panel=NSOpenPanel(); panel.canChooseDirectories=folder; panel.canChooseFiles = !folder; panel.allowsMultipleSelection=false
        return panel.runModal() == .OK ? panel.url?.path:nil
    }
    func revealStorage() { if let store { Task { let directory=await store.directory; NSWorkspace.shared.open(directory) } } }
    func export(format:ExportFormat,options:ExportOptions) async {
        guard let session=selectedSession,let store else { return }
        let panel=NSSavePanel(); panel.nameFieldStringValue=session.title+"."+format.rawValue
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try await SessionExporter(store:store).export(session:session,to:url,format:format,options:options); NSWorkspace.shared.activateFileViewerSelecting([url]) }
        catch { message=error.localizedDescription }
    }
}
