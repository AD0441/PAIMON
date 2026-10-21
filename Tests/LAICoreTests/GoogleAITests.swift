import Foundation
import Testing
@testable import LAICore

private actor MemoryGoogleKey:GoogleAICredentialStore {
    var value:String?
    init(_ value:String?="synthetic-key") { self.value=value }
    func read() -> String? { value }
    func save(_ value:String) { self.value=value }
    func delete() { value=nil }
}
private actor FixtureGoogleTransport:GoogleAITransport {
    var requests:[URLRequest]=[]
    let reply:GoogleAIHTTPReply
    let delay:Duration
    init(body:Data=Data(),status:Int=200,delay:Duration = .zero) { reply = .init(status:status,body:body); self.delay=delay }
    func send(_ request:URLRequest,maximumBytes:Int) async throws -> GoogleAIHTTPReply {
        requests.append(request)
        if delay != .zero { try await Task.sleep(for:delay) }
        return reply
    }
}
private actor RevokingGoogleKey:GoogleAICredentialStore {
    var reading=false
    var continuation:CheckedContinuation<String?,Never>?
    func read() async -> String? { reading=true; return await withCheckedContinuation{continuation=$0} }
    func save(_ value:String) {}
    func delete() { continuation?.resume(returning:"revoked-key"); continuation=nil }
}
private actor SequenceGoogleTransport:GoogleAITransport {
    var replies:[GoogleAIHTTPReply]
    var requests:[URLRequest]=[]
    init(_ replies:[GoogleAIHTTPReply]) { self.replies=replies }
    func send(_ request:URLRequest,maximumBytes:Int) -> GoogleAIHTTPReply {
        requests.append(request)
        return replies.count>1 ? replies.removeFirst():replies[0]
    }
}
private actor GoogleRetryDelays {
    var values:[Duration]=[]
    func record(_ value:Duration) { values.append(value) }
}
private func googleEnvelope(_ text:String,finish:String="STOP") throws -> Data {
    try JSONSerialization.data(withJSONObject:["candidates":[["content":["parts":[["text":text]]],"finishReason":finish]]])
}

@Test func googleIsDisabledByDefaultAndMissingKeysNeverSendRequests() async throws {
    let transport=FixtureGoogleTransport(),keys=MemoryGoogleKey(nil)
    let client=GoogleAIClient(credentials:keys,transport:transport)
    do { _=try await client.testConnection(model:GoogleAIClient.defaultModel); Issue.record("Disabled client connected") }
    catch { #expect(error as? GoogleAIError == .disabled) }
    await client.setEnabled(true)
    do { _=try await client.testConnection(model:GoogleAIClient.defaultModel); Issue.record("Missing key connected") }
    catch { #expect(error as? GoogleAIError == .missingKey) }
    #expect(await transport.requests.isEmpty)
    #expect(AppSettings().googleEnabled != true)
    #expect(AppSettings().summary == .apple)
}
@Test func googleOptInNeverChangesHistoricalSessionOrLegacyLocalBackend() throws {
    let historical=AppSettings()
    var preferences=historical; preferences.googleEnabled=true; preferences.googleModel="gemini-test"
    let newlySelected=preferences.forNewSession()
    #expect(historical.summaryBackend(googleAllowed:true) == .apple)
    #expect(newlySelected.summaryBackend(googleAllowed:true) == .google)
    #expect(newlySelected.summaryBackend(googleAllowed:false) == .apple)
    let object=try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(newlySelected)) as? [String:Any])
    #expect(object["summary"] as? String == "apple")
    #expect(object["googleSummarySelected"] as? Bool == true)
}
@Test func googleConnectionProbeSendsNoTranscriptAndKeepsKeyOutOfURL() async throws {
    let body=Data(#"{"displayName":"Synthetic Gemini","supportedGenerationMethods":["generateContent"]}"#.utf8)
    let transport=FixtureGoogleTransport(body:body),keys=MemoryGoogleKey()
    let client=GoogleAIClient(credentials:keys,transport:transport)
    await client.setEnabled(true)
    #expect(try await client.testConnection(model:GoogleAIClient.defaultModel)=="Synthetic Gemini")
    let request=try #require(await transport.requests.first)
    #expect(request.httpMethod=="GET"); #expect(request.httpBody==nil)
    #expect(request.url?.host=="generativelanguage.googleapis.com")
    #expect(request.url?.query==nil); #expect(request.value(forHTTPHeaderField:"x-goog-api-key")=="synthetic-key")
    try await client.saveKey(" replacement "); #expect(await keys.read()=="replacement")
    try await client.deleteKey(); #expect(try await !client.hasKey())
}
@Test func googleRejectsEndpointInjection() throws {
    for model in ["https://example.com/gemini","gemini-test?key=other","gemini-test/../../models","gemini-test\nheader:value",""] {
        #expect(throws:GoogleAIError.self) { try GoogleAIClient.normalizedModel(model) }
    }
    #expect(try GoogleAIClient.normalizedModel("models/gemini-test")=="gemini-test")
}
@Test func googleStructuredSummaryUsesOnlyTextAndOriginalEvidence() async throws {
    let draft=#"{"title":"Compra de micrófonos","overview":"Se revisó el presupuesto del laboratorio y se acordó comprar dos micrófonos.","points":[{"kind":"decision","text":"Comprar dos micrófonos","sources":["S0"],"owner":"Sebastián","due":"mañana"},{"kind":"decision","text":"Decidir dónde instalar los equipos","sources":["S0"],"owner":"","due":""}]}"#
    let transport=FixtureGoogleTransport(body:try googleEnvelope(draft))
    let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport)
    await client.setEnabled(true)
    let context=SessionContext(objective:"Sebastián debe instalar los equipos mañana")
    let engine=GoogleSummaryEngine(client:client,model:"gemini-test",context:context)
    let segment=TranscriptSegment(sessionID:UUID(),source:.system,start:4,end:15,text:"Revisamos el presupuesto del laboratorio. Acordamos comprar dos micrófonos. Falta decidir dónde instalar los equipos.")
    let result=try await engine.summarize(segments:[segment],previous:[],final:false,locale:"es-ES")
    let decision=try #require(result.first{$0.kind == .decision})
    #expect(decision.text=="Comprar dos micrófonos"); #expect(decision.owner==nil); #expect(decision.due==nil)
    #expect(decision.quote==segment.text); #expect(decision.start==4); #expect(decision.end==15)
    #expect(result.filter{$0.kind == .decision}.count==1)
    let request=try #require(await transport.requests.first)
    let requestBody=try #require(request.httpBody)
    let object=try JSONSerialization.jsonObject(with:requestBody)
    let payload=try #require(object as? [String:Any])
    #expect(Set(payload.keys)==["systemInstruction","contents","generationConfig"])
    let contents=try #require(payload["contents"] as? [[String:Any]])
    let parts=try #require(contents.first?["parts"] as? [[String:Any]])
    let firstPart=try #require(parts.first)
    #expect(Set(firstPart.keys)==["text"])
    let prompt=try #require(parts.first?["text"] as? String)
    #expect(prompt.contains(segment.text)); #expect(!prompt.contains(segment.sessionID.uuidString))
    #expect(!String(decoding:requestBody,as:UTF8.self).contains("synthetic-key"))
}
@Test func googleRejectsTruncationBlockingAndOversizedReplies() async throws {
    #expect(throws:GoogleAIError.incomplete) { try GoogleAIClient.decodeContent(googleEnvelope("{}",finish:"MAX_TOKENS")) }
    #expect(throws:GoogleAIError.blocked) { try GoogleAIClient.decodeContent(Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8)) }
    let transport=FixtureGoogleTransport(body:Data(repeating:32,count:256*1024+1))
    let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport); await client.setEnabled(true)
    do { _=try await client.testConnection(model:"gemini-test"); Issue.record("Oversized response accepted") }
    catch { #expect(error as? GoogleAIError == .responseTooLarge) }
}
@Test func googleErrorsDoNotExposeServiceResponseAndDoNotRetry() async throws {
    let transport=FixtureGoogleTransport(body:Data("private text and synthetic-key".utf8),status:429)
    let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport); await client.setEnabled(true)
    do { _=try await client.testConnection(model:"gemini-test"); Issue.record("Quota failure accepted") }
    catch { #expect(error as? GoogleAIError == .http(429)); #expect(!error.localizedDescription.contains("private text")); #expect(!error.localizedDescription.contains("synthetic-key")) }
    #expect(await transport.requests.count==1)
}
@Test(.timeLimit(.minutes(1))) func disablingGoogleCancelsInFlightRequest() async throws {
    let transport=FixtureGoogleTransport(delay:.seconds(30))
    let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport); await client.setEnabled(true)
    let work=Task { try await client.testConnection(model:"gemini-test") }
    while await transport.requests.isEmpty { try await Task.sleep(for:.milliseconds(5)) }
    await client.setEnabled(false)
    do { _=try await work.value; Issue.record("Disabled request completed") } catch is CancellationError {}
    #expect(await transport.requests.count==1)
}
@Test(.timeLimit(.minutes(1))) func deletingKeyWhileItIsBeingReadPreventsTransmission() async throws {
    let credentials=RevokingGoogleKey(),transport=FixtureGoogleTransport()
    let client=GoogleAIClient(credentials:credentials,transport:transport); await client.setEnabled(true)
    let work=Task { try await client.testConnection(model:"gemini-test") }
    while await !credentials.reading { try await Task.sleep(for:.milliseconds(5)) }
    try await client.deleteKey()
    do { _=try await work.value; Issue.record("Revoked key was sent") }
    catch { #expect(error as? GoogleAIError == .configurationChanged) }
    #expect(await transport.requests.isEmpty)
}
@Test func googleRetriesTemporaryServerFailuresWithBoundedBackoff() async throws {
    let body=try googleEnvelope("{}")
    let transport=SequenceGoogleTransport([.init(status:503,body:Data(),retryAfter:3),.init(status:502,body:Data()),.init(status:200,body:body)])
    let delays=GoogleRetryDelays()
    let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport,retryPause:{ await delays.record($0) })
    await client.setEnabled(true)
    #expect(try await client.generate(model:"gemini-test",instructions:"Synthetic test",prompt:"Synthetic transcript",schema:Data("{}".utf8))==Data("{}".utf8))
    let requests=await transport.requests
    #expect(requests.count==3)
    #expect(requests.allSatisfy{$0.httpMethod=="POST" && $0.httpBody==requests[0].httpBody})
    let waits=await delays.values
    #expect(waits.count==2)
    #expect(waits[0] >= .seconds(3)); #expect(waits[0] <= .milliseconds(3500))
    #expect(waits[1] >= .seconds(4)); #expect(waits[1] <= .milliseconds(4500))
    #expect(await client.retryStatus==nil)
}
@Test func googleRetryLimitAndLongServerWaitPreserveSafeErrors() async throws {
    for retryAfter:TimeInterval? in [nil,120] {
        let transport=SequenceGoogleTransport([.init(status:503,body:Data("private response".utf8),retryAfter:retryAfter)])
        let delays=GoogleRetryDelays()
        let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport,retryPause:{ await delays.record($0) })
        await client.setEnabled(true)
        do { _=try await client.testConnection(model:"gemini-test"); Issue.record("Unavailable service accepted") }
        catch {
            #expect(error as? GoogleAIError == .http(503))
            #expect(error.localizedDescription.contains("temporalmente"))
            #expect(!error.localizedDescription.contains("private response"))
        }
        #expect(await transport.requests.count==(retryAfter==nil ? 3:1))
        #expect(await delays.values.count==(retryAfter==nil ? 2:0))
    }
    #expect(GoogleAIURLTransport.retryAfter("7")==7)
    #expect(GoogleAIURLTransport.retryAfter("invalid")==nil)
    #expect(GoogleAIURLTransport.retryAfter("nan")==nil)
}
@Test(.timeLimit(.minutes(1))) func revokingGoogleDuringBackoffPreventsAnotherTransmission() async throws {
    let transport=SequenceGoogleTransport([.init(status:503,body:Data())])
    let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport,retryPause:{ _ in try await Task.sleep(for:.seconds(30)) })
    await client.setEnabled(true)
    let work=Task { try await client.testConnection(model:"gemini-test") }
    while await client.retryStatus==nil { try await Task.sleep(for:.milliseconds(5)) }
    try await client.deleteKey()
    do { _=try await work.value; Issue.record("Revoked retry completed") } catch is CancellationError {}
    #expect(await transport.requests.count==1)
    #expect(await client.retryStatus==nil)
}
@Test func googleClientErrorsNeverTriggerAutomaticRetries() async throws {
    for status in [400,401,403,404,429] {
        let transport=SequenceGoogleTransport([.init(status:status,body:Data())])
        let delays=GoogleRetryDelays()
        let client=GoogleAIClient(credentials:MemoryGoogleKey(),transport:transport,retryPause:{ await delays.record($0) })
        await client.setEnabled(true)
        do { _=try await client.testConnection(model:"gemini-test"); Issue.record("Client error accepted") }
        catch { #expect(error as? GoogleAIError == .http(status)) }
        #expect(await transport.requests.count==1); #expect(await delays.values.isEmpty)
    }
}
