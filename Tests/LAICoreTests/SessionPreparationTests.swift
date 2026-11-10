import AVFoundation
import Foundation
import Testing
@testable import LAICore

private actor IdentifiedSummary:SummarizationEngine {
    let identity:String
    var calls=0
    init(_ identity:String) { self.identity=identity }
    func identifier() -> String? { identity }
    func availability(locale:String) -> String? { nil }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) -> [Finding] {
        calls += 1
        guard let segment=segments.first else { return previous }
        return [.init(kind:.overview,text:segment.text,segmentID:segment.id,quote:segment.text,start:segment.start,end:segment.end)]
    }
    func unload() {}
}
private actor ImportTestEngine:TranscriptionEngine {
    var id=UUID()
    var events:AsyncStream<PipelineEvent>.Continuation?
    var receivedAudio:[AudioChunk]=[]
    var maximumSamples:Int { receivedAudio.map { $0.samples.count }.max() ?? 0 }
    var seenSources:Set<AudioSource> { Set(receivedAudio.map(\.source)) }
    let failAfter:Int?
    init(failAfter:Int?=nil) { self.failAfter=failAfter }
    func start(sessionID:UUID,sources:[AudioSource],settings:AppSettings,events:AsyncStream<PipelineEvent>.Continuation) { id=sessionID; self.events=events }
    func append(_ chunk:AudioChunk) async throws {
        receivedAudio.append(chunk)
        if receivedAudio.count==1,let events { try await SpeechEventDelivery.emit(.init(sessionID:id,source:.file,start:0,end:0.1,text:"Texto definitivo de prueba"),to:events) }
        if let failAfter,receivedAudio.count>=failAfter { throw LAIError.message("Synthetic import failure") }
    }
    func finish() {}
    func cancel() {}
}

@Test(.timeLimit(.minutes(1))) func importClosesEventsWhenInitialSaveFails() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    var session=Session(title:"Invalid initial save",settings:AppSettings()); session.duration = .nan
    let pair=AsyncStream<PipelineEvent>.makeStream()
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    await #expect(throws:EncodingError.self) {
        _=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation,engineOverride:ImportTestEngine())
    }
    var events=0
    for await _ in pair.stream { events += 1 }
    #expect(events==0)
}

@Test func sessionContextIsBoundedStableAndBackwardsCompatible() throws {
    let context=SessionContext(objective:String(repeating:"o",count:300),agenda:String(repeating:"a",count:900),glossary:String(repeating:"g",count:700))
    #expect(context.bounded.objective.count==250); #expect(context.bounded.agenda.count==600); #expect(context.bounded.glossary.count==350)
    #expect(context.engineIdentifier(backend:"apple")==context.bounded.engineIdentifier(backend:"apple"))
    #expect(context.engineIdentifier(backend:"apple") != context.engineIdentifier(backend:"google"))
    var object=try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(Session(title:"Old",settings:AppSettings()))) as? [String:Any])
    object.removeValue(forKey:"context"); object.removeValue(forKey:"importedFileName")
    let old=try JSONDecoder().decode(Session.self,from:JSONSerialization.data(withJSONObject:object))
    #expect(old.context==nil); #expect(old.settings.googleEnabled != true)
    #expect(old.settings.enhanceImportedAudio != true)
}
@Test func executiveViewSelectsExistingFindingsWithoutChangingEvidence() {
    let facts:[Finding]=(0..<20).map { index in
        let kind:FindingKind
        if index==0 { kind = .overview }
        else if index==1 { kind = .idea }
        else { kind=index%2==0 ? .decision:.task }
        return Finding(kind:kind,text:"Punto \(index)",segmentID:"system-\(index)",quote:"Evidencia \(index)",start:Double(index),end:Double(index+1))
    }
    let selected=ReportPresentation.executive.select(facts)
    #expect(selected.first==facts.first); #expect(!selected.contains{$0.kind == .idea})
    #expect(selected.filter{$0.kind == .task}.count==5); #expect(selected.filter{$0.kind == .decision}.count==5)
    #expect(ReportPresentation.complete.select(facts)==facts)
    #expect(selected.allSatisfy{fact in facts.contains(fact)})
}
@Test func frequentTermsIgnoreAccentsPartialsAndEchoes() {
    let id=UUID()
    let first=TranscriptSegment(sessionID:id,source:.file,start:0,end:5,text:"Micrófonos, micrófonos y presupuesto. El presupuesto del laboratorio.")
    let partial=TranscriptSegment(sessionID:id,source:.file,start:6,end:7,text:"parcial parcial parcial",isFinal:false)
    var echo=first; echo.duplicateOf=first.id
    let ranked=SessionTerm.rank([first,partial,echo])
    #expect(ranked.contains(.init(text:"microfonos",count:2))); #expect(ranked.contains(.init(text:"presupuesto",count:2)))
    #expect(!ranked.contains{$0.text=="parcial" || $0.text=="laboratorio"})
}
@Test func progressUsesPersistedCursorAndBackendChangeRebuilds() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Cursor",settings:AppSettings())
    try await store.save(session)
    try await store.append(.init(sessionID:session.id,source:.file,start:0,end:5,text:"Acordamos comprar equipos para el laboratorio."))
    let coordinator=SummaryCoordinator(store:store),first=IdentifiedSummary("google:model:context")
    _=try await coordinator.update(session:session,engine:first,final:true)
    let stored=try await store.latestSummary(session:session.id)
    #expect(stored?.engineIdentifier=="google:model:context")
    try await store.append(.init(sessionID:session.id,source:.file,start:5,end:12,text:"Revisamos el presupuesto para los equipos."))
    let progress=try await store.processingProgress(session:session.id)
    #expect(progress.transcribedThrough==12); #expect(progress.summarizedThrough==5); #expect(progress.pendingSegments==1); #expect(!progress.isFinal)
    let second=IdentifiedSummary("apple::different-context")
    _=try await coordinator.update(session:session,engine:second,final:true)
    #expect(await second.calls==2)
    #expect(try await store.latestSummary(session:session.id)?.engineIdentifier=="apple::different-context")
}
@Test func audioImportPersistsFinalsAndBoundsPCMBuffers() async throws {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    let fixture=root.appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Imported",settings:AppSettings()),engine=ImportTestEngine()
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
    let completed=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation,engineOverride:engine)
    #expect(completed.status=="completed"); #expect(completed.duration>5); #expect(completed.importedFileName=="spanish-synthetic.aiff")
    #expect(await engine.maximumSamples<=4096); #expect(await engine.seenSources==[.file])
    #expect(try await store.segments(session:session.id).count==1)
    #expect(try await store.segments(session:session.id,search:"DEFINITÍVO").count==1)
    #expect(!FileManager.default.fileExists(atPath:directory.appendingPathComponent(session.id.uuidString).path))
}
@Test func importLevelingBoostsQuietSignalAndLimitsPeaksOnlyWhenEnabled() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let fixture=directory.appendingPathComponent("levels.caf")
    let blockSize=4096
    let quiet=(0..<blockSize).map { $0.isMultiple(of:2) ? Float(0.02):Float(-0.02) }
    var peaks=quiet
    peaks[0]=1
    peaks[1] = -1
    let silence=Array(repeating:Float(0),count:blockSize)
    let tail=Array(repeating:Float(0.0001),count:173)
    let original=quiet+peaks+silence+tail
    let sampleRate=16000.0
    let format=try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:sampleRate,channels:1,interleaved:false))
    do {
        let file=try AVAudioFile(forWriting:fixture,settings:format.settings,commonFormat:.pcmFormatFloat32,interleaved:false)
        let buffer=try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(original.count)))
        buffer.frameLength=AVAudioFrameCount(original.count)
        let channel=try #require(buffer.floatChannelData)[0]
        for index in original.indices { channel[index]=original[index] }
        try file.write(from:buffer)
    }
    let originalFile=try Data(contentsOf:fixture)
    let raw=ImportTestEngine(),enhanced=ImportTestEngine()
    for (enabled,engine) in [(false,raw),(true,enhanced)] {
        var settings=AppSettings()
        settings.enhanceImportedAudio=enabled
        let session=Session(title:"Import leveling",settings:settings.forNewSession())
        let events=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
        let completed=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:events.continuation,engineOverride:engine)
        #expect(completed.settings.enhanceImportedAudio==enabled)
        #expect(completed.duration==Double(original.count)/sampleRate)
    }
    let unprocessed=await raw.receivedAudio,processed=await enhanced.receivedAudio
    #expect(unprocessed.flatMap(\.samples)==original)
    try #require(processed.count==4)
    #expect(processed.map { $0.samples.count }==[blockSize,blockSize,blockSize,tail.count])
    #expect(processed.map(\.start)==unprocessed.map(\.start))
    #expect(processed.allSatisfy { $0.sampleRate==sampleRate && $0.source == .file })
    #expect(processed[0].samples.allSatisfy { abs($0)>0.07 && abs($0)<0.09 })
    #expect(processed[1].samples[0]>0.70 && processed[1].samples[0]<0.97)
    #expect(processed[1].samples[1] < -0.70 && processed[1].samples[1] > -0.97)
    #expect(processed[2].samples==silence)
    #expect(processed[3].samples.allSatisfy { abs($0)<=0.000101 })
    #expect(try Data(contentsOf:fixture)==originalFile)
}
@Test func interruptedImportPreservesAlreadyRecognizedText() async throws {
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory),session=Session(title:"Interrupted import",settings:AppSettings()),engine=ImportTestEngine(failAfter:8)
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
    do { _=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation,engineOverride:engine); Issue.record("Failure accepted") } catch {}
    #expect(try await store.session(id:session.id)?.status=="interrupted")
    #expect(try await store.segments(session:session.id).count==1)
}
@Test(.enabled(if:ProcessInfo.processInfo.environment["PAIMON_TEST_NATIVE_IMPORT"]=="1"),.timeLimit(.minutes(1)),.serialized,arguments:[false,true])
func nativeAudioImportProducesRealSpanishText(_ enhanceAudio:Bool) async throws {
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    var settings=AppSettings()
    settings.enhanceImportedAudio=enhanceAudio
    let store=try SessionStore(directory:directory),session=Session(title:"Native import",settings:settings)
    let pair=AsyncStream<PipelineEvent>.makeStream(bufferingPolicy:.bufferingNewest(8))
    _=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:pair.continuation)
    let text=try await store.segments(session:session.id).map{$0.1.text}.joined(separator:" ").lowercased()
    #expect(text.contains("micrófonos")); #expect(text.contains("cotización")); #expect(text.contains("viernes"))
}

@Test(arguments:[false,true])
func optionalDiarizationKeepsImportAndPersistsLabels(_ enabled:Bool) async throws {
    let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/spanish-synthetic.aiff")
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let executable=directory.appendingPathComponent("fixture-worker")
    try """
    #!/bin/sh
    [ "$1" = "--diarize" ] || exit 2
    while IFS= read -r request; do
      printf '%s\\n' '{"turns":[{"speaker":"a","start":0,"end":4}]}'
    done
    """.write(to:executable,atomically:true,encoding:.utf8)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
    var settings=AppSettings()
    settings.diarizationEnabled=enabled
    settings.fluidWorker=executable.path
    settings.diarizationModels=directory.path
    let session=Session(title:"Importación con voces",settings:settings)
    let events=AsyncStream<PipelineEvent>.makeStream()
    let completed=try await AudioFileTranscriber.importSession(url:fixture,session:session,store:store,events:events.continuation,engineOverride:ImportTestEngine())
    #expect(completed.status=="completed")
    let rows=try await store.segments(session:session.id).map(\.1)
    #expect(rows.count==1)
    #expect(rows.first?.text=="Texto definitivo de prueba")
    let speakers=try await store.speakers(for:rows,session:session.id)
    #expect(speakers.values.first?.id==(enabled ? "file:a":nil))
    var updated=false
    for await event in events.stream {
        if case .speakersUpdated(let id)=event,id==session.id { updated=true }
        if case .warning(let message)=event { Issue.record("Unexpected warning: \(message)") }
    }
    #expect(updated==enabled)
}

@Test func speakerAlignmentKeepsSourcesSeparateAndAvoidsAmbiguousLabels() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Dos fuentes",settings:AppSettings())
    try await store.save(session)
    try await store.appendSpeakerTurns([
        SpeakerTurn(speaker:"system:a",start:1,end:4),
        SpeakerTurn(speaker:"system:b",start:4,end:8),
        SpeakerTurn(speaker:"system:a",start:10,end:13)
    ],source:.system,session:session.id)
    try await store.appendSpeakerTurns([SpeakerTurn(speaker:"microphone:a",start:1,end:4)],source:.microphone,session:session.id)
    let system=TranscriptSegment(sessionID:session.id,source:.system,start:1.25,end:3.75,text:"Sistema")
    let mixed=TranscriptSegment(sessionID:session.id,source:.system,start:3,end:5,text:"Dos voces")
    let microphone=TranscriptSegment(sessionID:session.id,source:.microphone,start:1.25,end:3.75,text:"Micrófono")
    let later=TranscriptSegment(sessionID:session.id,source:.system,start:10.25,end:12.75,text:"Repetición")
    let segments=[system,mixed,microphone,later]
    var labels=try await store.speakers(for:segments,session:session.id)
    #expect(labels[system.id]?.number==1)
    #expect(labels[mixed.id]==nil)
    #expect(labels[microphone.id]?.id=="microphone:a")
    try await store.renameSpeaker(session:session.id,id:"system:a",name:"  Voz Alfa ")
    let reopened=try SessionStore(directory:directory)
    labels=try await reopened.speakers(for:segments,session:session.id)
    #expect(labels[system.id]?.name=="Voz Alfa")
    #expect(labels[later.id]?.name=="Voz Alfa")
    #expect(labels[microphone.id]?.name==nil)
    try await reopened.delete(session:session.id)
    #expect(try await store.speakers(for:segments,session:session.id).isEmpty)
}

@Test(arguments:OptionalModelPackage.allCases,[false,true])
func optionalModelInstallationVerifiesFilesBeforeSelectingThem(_ package:OptionalModelPackage,_ corrupt:Bool) async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let destination=root.appendingPathComponent("installed")
    let asset=OptionalModelPackage.Asset("speaker.mlmodelc/weights.bin",3,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    let fetch:@Sendable (URL,OptionalModelPackage.Asset,Int) async throws -> URL = { url,_,_ in
        #expect(url.host=="huggingface.co")
        #expect(url.path.hasSuffix("/speaker.mlmodelc/weights.bin"))
        let temporary=root.appendingPathComponent("download")
        try Data((corrupt ? "bad":"abc").utf8).write(to:temporary)
        return temporary
    }
    if corrupt {
        await #expect(throws:LAIError.self) {
            _=try await package.install(at:destination,assets:[asset],fetch:fetch,progress:{ _ in })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
    } else {
        let result=try await package.install(at:destination,assets:[asset],fetch:fetch,progress:{ _ in })
        #expect(result==destination)
        #expect(try Data(contentsOf:result.appendingPathComponent(asset.path))==Data("abc".utf8))
        _=try await package.install(at:destination,assets:[asset],fetch:{ _,_,_ in
            Issue.record("An intact model was downloaded again")
            throw LAIError.message("Unexpected network request")
        },progress:{ _ in })
        #expect(try FileManager.default.contentsOfDirectory(atPath:root.path)==["installed"])
    }
}

@Test func failedMLXRuntimePreparationDoesNotPublishModelWeights() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let destination=root.appendingPathComponent("installed")
    let asset=OptionalModelPackage.Asset("model.safetensors",3,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    await #expect(throws:LAIError.self) {
        _=try await OptionalModelPackage.mlx.install(at:destination,assets:[asset],fetch:{ _,_,_ in
            let file=root.appendingPathComponent("download")
            try Data("abc".utf8).write(to:file)
            return file
        },prepare:{ staging in
            #expect(FileManager.default.fileExists(atPath:staging.appendingPathComponent(asset.path).path))
            throw LAIError.message("Fixture runtime preparation failure")
        },progress:{ _ in })
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
}
