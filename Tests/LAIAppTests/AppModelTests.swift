import Foundation
import Testing
@testable import LAIApp
import LAICore

actor ControlledSummary:SummarizationEngine {
    enum Outcome:String,CaseIterable,Sendable { case unavailable,success,failure }
    let outcome:Outcome
    private var entered=false
    private var observer:CheckedContinuation<Void,Never>?
    private var suspended:CheckedContinuation<Void,Never>?
    private(set) var unloads=0
    init(_ outcome:Outcome) { self.outcome=outcome }
    private func suspend() async {
        await withCheckedContinuation { continuation in
            suspended=continuation; entered=true; observer?.resume(); observer=nil
        }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { observer=$0 }
    }
    func release() { suspended?.resume(); suspended=nil }
    func availability(locale:String) async -> String? {
        if outcome == .unavailable { await suspend(); return "Motor no disponible en esta prueba" }
        return nil
    }
    func summarize(segments:[TranscriptSegment],previous:[Finding],final:Bool,locale:String) async throws -> [Finding] {
        if !entered { await suspend() }
        if outcome == .failure { throw LAIError.message("Error controlado de la sesión anterior") }
        guard let first=segments.first else { return previous }
        return [Finding(kind:.overview,text:first.text,segmentID:first.id,quote:first.text,start:first.start,end:first.end)]
    }
    func unload() { unloads += 1 }
}

@MainActor
private struct ModelFixture {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("PAIMON-AppTests-\(UUID())")
    let suite="PAIMON-AppTests-\(UUID())"
    let defaults:UserDefaults
    let store:SessionStore
    init() throws { defaults=try #require(UserDefaults(suiteName:suite)); store=try SessionStore(directory:directory) }
    func clean() { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:directory) }
    func model(engine:ControlledSummary?=nil) -> AppModel {
        let factory:(@MainActor (Session?) -> any SummarizationEngine)?
        if let engine { factory={ _ in engine } } else { factory=nil }
        return AppModel(store:store,preferences:defaults,summaryEngine:factory)
    }
    func session(_ title:String) async throws -> Session {
        var session=Session(title:title,settings:AppSettings()); session.status="stopped"
        try await store.save(session)
        try await store.append(TranscriptSegment(sessionID:session.id,source:.file,start:0,end:8,text:"Acordamos revisar el presupuesto de \(title) antes de comprar los equipos."))
        return session
    }
}

@Suite(.serialized,.timeLimit(.minutes(1))) @MainActor
struct AppModelTests {
    @Test(arguments:ControlledSummary.Outcome.allCases)
    func summaryCompletionDoesNotReplaceAnotherSessionsStatus(_ outcome:ControlledSummary.Outcome) async throws {
        let fixture=try ModelFixture(); defer { fixture.clean() }
        let a=try await fixture.session("Laboratorio"),b=try await fixture.session("Biblioteca")
        let engine=ControlledSummary(outcome),model=fixture.model(engine:engine)
        await model.select(a.id)
        let pending=Task { await model.updateSummary(final:true) }
        await engine.waitForEntry()
        await model.select(b.id)
        let expected=model.summaryStatus
        await engine.release(); await pending.value
        #expect(model.selected==b.id)
        #expect(model.summaryStatus==expected)
        #expect(model.findings.isEmpty)
        #expect(await engine.unloads==1)
        #expect(model.summaryWorking==false)
    }

    @Test func checkingAvailabilityPreservesStoredSummaryStatus() async throws {
        let fixture=try ModelFixture(); defer { fixture.clean() }
        let session=try await fixture.session("Biblioteca"),engine=ControlledSummary(.unavailable)
        let model=fixture.model(engine:engine)
        await model.select(session.id); model.summaryStatus="Síntesis final guardada"
        let checking=Task { await model.checkAvailability() }
        await engine.waitForEntry(); await engine.release(); await checking.value
        #expect(model.summaryStatus=="Síntesis final guardada")
        #expect(model.summaryAvailability=="Motor no disponible en esta prueba")
        #expect(await engine.unloads==1)
    }

    @Test func searchKeepsSummaryBookmarksAndEvidenceNavigation() async throws {
        let fixture=try ModelFixture(); defer { fixture.clean() }
        let session=try await fixture.session("Laboratorio"),model=fixture.model()
        let bookmark=SessionBookmark(sessionID:session.id,time:3,segmentID:nil)
        try await fixture.store.save(bookmark)
        await model.select(session.id); model.summaryStatus="Resumen guardado"
        model.transcriptSearch="presupuesto"; await model.filterTranscript()
        #expect(model.segments.count==1)
        #expect(model.bookmarks.map(\.id)==[bookmark.id])
        #expect(model.summaryStatus=="Resumen guardado")
        let segment=try #require(model.segments.first)
        await model.revealTranscriptSegment(segment.id)
        let window=model.segments
        await model.filterTranscript()
        #expect(model.transcriptTarget==segment.id)
        #expect(model.segments==window)
        model.newSession()
        #expect(model.canLoadEarlier==false); #expect(model.transcriptSearch.isEmpty)
        #expect(model.sessionContext.isEmpty); #expect(model.selected==nil)
    }

    @Test func cancelledSearchDoesNotReplaceVisibleTranscript() async throws {
        let fixture=try ModelFixture(); defer { fixture.clean() }
        let session=try await fixture.session("Laboratorio"),model=fixture.model()
        await model.select(session.id)
        let visible=model.segments
        model.transcriptSearch="sin coincidencias"
        let search=Task { await model.filterTranscript() }; search.cancel(); await search.value
        #expect(model.segments==visible)
    }

    @Test(arguments:AppPalette.allCases)
    func palettePersistsWithoutChangingPrivateEnginePreferences(_ palette:AppPalette) throws {
        let fixture=try ModelFixture(); defer { fixture.clean() }
        let model=fixture.model(); model.settings.colorPalette=palette
        let restored=AppSettings.load(from:fixture.defaults)
        #expect(restored.colorPalette==palette)
        #expect(restored.googleEnabled != true)
        #expect(restored.saveAudio==false)
        var legacy=try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(restored)) as? [String:Any])
        legacy.removeValue(forKey:"colorPalette")
        let decoded=try JSONDecoder().decode(AppSettings.self,from:JSONSerialization.data(withJSONObject:legacy))
        #expect(decoded.colorPalette==nil)
    }

    @Test(arguments:AppLanguage.allCases)
    func interfaceLanguageKeepsRecognitionAndSessionSettings(_ language:AppLanguage) throws {
        let fixture=try ModelFixture(); defer { fixture.clean() }
        let model=fixture.model(); model.settings.locale="es-ES"; model.settings.interfaceLanguage=language
        let restored=AppSettings.load(from:fixture.defaults)
        #expect(restored.interfaceLanguage==language)
        #expect(restored.locale=="es-ES")
        #expect(restored.forNewSession().locale=="es-ES")
        #expect(restored.googleEnabled != true)
        var legacy=try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(restored)) as? [String:Any])
        legacy.removeValue(forKey:"interfaceLanguage")
        #expect(try JSONDecoder().decode(AppSettings.self,from:JSONSerialization.data(withJSONObject:legacy)).interfaceLanguage==nil)
    }

    @Test func localizedCatalogPreservesFormatArguments() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let object=try #require(try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Resources/Localizable.xcstrings"))) as? [String:Any])
        let strings=try #require(object["strings"] as? [String:[String:Any]])
        let format=try NSRegularExpression(pattern:"%(?:[0-9]+\\$)?(?:lld|ld|d|@|[0-9.]*f)")
        func placeholders(_ value:String) -> [String] {
            format.matches(in:value,range:NSRange(value.startIndex...,in:value)).compactMap{Range($0.range,in:value).map{String(value[$0])}}.sorted()
        }
        #expect(strings.count>=230)
        for (key,entry) in strings {
            let localizations=try #require(entry["localizations"] as? [String:[String:Any]])
            let unit=try #require(localizations["en"]?["stringUnit"] as? [String:String])
            let value=try #require(unit["value"])
            #expect(value.isEmpty==false)
            #expect(placeholders(key)==placeholders(value),"Formato de \(key)")
        }
    }
}
