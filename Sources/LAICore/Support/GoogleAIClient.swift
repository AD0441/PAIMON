import Foundation
import Security

public enum GoogleAIError:LocalizedError,Sendable,Equatable {
    case disabled, missingKey, configurationChanged, invalidModel, keychain(Int32), busy, responseTooLarge, incomplete, blocked, offline, timeout, http(Int)
    public var errorDescription:String? {
        switch self {
        case .disabled:"Google AI está desactivado. Actívalo en Configuración y selecciona esta sesión para enviar texto."
        case .missingKey:"Falta la clave de Google AI. Guárdala en Configuración → Google AI."
        case .configurationChanged:"La configuración de Google AI cambió. Vuelve a intentarlo."
        case .invalidModel:"Introduce un identificador de modelo Gemini válido, sin URL."
        case .keychain(let code):"No se pudo acceder al Llavero de macOS (\(code))."
        case .busy:"Hay una solicitud a Google AI en curso. Espera a que termine."
        case .responseTooLarge:"Google AI excedió el tamaño de respuesta permitido. La transcripción está guardada."
        case .incomplete:"Google AI devolvió una respuesta incompleta. La transcripción está guardada."
        case .blocked:"Google AI no generó contenido para este texto. La transcripción está guardada."
        case .offline:"No hay conexión con Google AI. Puedes usar el motor local o reintentar."
        case .timeout:"Google AI tardó demasiado. La transcripción está guardada; reintenta manualmente."
        case .http(400):"Google AI rechazó la configuración de la solicitud o del modelo (400)."
        case .http(401),.http(403):"Google AI rechazó la clave o sus permisos. Revísala en AI Studio."
        case .http(404):"El modelo no está disponible para esta clave. Revisa su nombre en AI Studio."
        case .http(429):"Google AI alcanzó su cuota o límite de solicitudes. Reintenta más tarde."
        case .http(503):"Google AI está temporalmente saturado o no disponible (503). Reintenta más tarde con Actualizar resumen o selecciona el motor local. La transcripción y el resumen anterior siguen guardados."
        case .http(500),.http(502),.http(504):"Google AI tiene un fallo temporal del servicio. Reintenta más tarde con Actualizar resumen; el contenido guardado se conserva."
        case .http(let status):"Google AI no pudo completar la solicitud (HTTP \(status))."
        }
    }
}

protocol GoogleAICredentialStore:Sendable {
    func read() async throws -> String?
    func save(_ value:String) async throws
    func delete() async throws
}

actor GoogleAIKeychain:GoogleAICredentialStore {
    private let service:String
    init(service:String="local.audio.intelligence.google-ai") { self.service=service }
    private var query:[String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal-api-key",kSecAttrSynchronizable as String:false] }
    func read() throws -> String? {
        var query=query
        query[kSecReturnData as String]=true; query[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess else { throw GoogleAIError.keychain(status) }
        return (result as? Data).flatMap{String(data:$0,encoding:.utf8)}
    }
    func save(_ value:String) throws {
        let bytes=Data(value.utf8)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if status==errSecItemNotFound {
            var item=query; item[kSecValueData as String]=bytes
            item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added=SecItemAdd(item as CFDictionary,nil)
            guard added==errSecSuccess else { throw GoogleAIError.keychain(added) }
        } else if status != errSecSuccess { throw GoogleAIError.keychain(status) }
    }
    func delete() throws {
        let status=SecItemDelete(query as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else { throw GoogleAIError.keychain(status) }
    }
}

struct GoogleAIHTTPReply:Sendable { var status:Int; var body:Data; var retryAfter:TimeInterval?=nil }
protocol GoogleAITransport:Sendable {
    func send(_ request:URLRequest,maximumBytes:Int) async throws -> GoogleAIHTTPReply
}

/// No cross-host redirects may forward the API key. This delegate has no state.
private final class GoogleAINoRedirect:NSObject,URLSessionTaskDelegate,Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable (URLRequest?)->Void) { completionHandler(nil) }
}
struct GoogleAIURLTransport:GoogleAITransport {
    func send(_ request:URLRequest,maximumBytes:Int) async throws -> GoogleAIHTTPReply {
        let config=URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies=false; config.urlCache=nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session=URLSession(configuration:config,delegate:GoogleAINoRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse else { throw GoogleAIError.incomplete }
        guard response.expectedContentLength<=Int64(maximumBytes) else { throw GoogleAIError.responseTooLarge }
        var data=Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count<maximumBytes else { throw GoogleAIError.responseTooLarge }
            data.append(byte)
        }
        return .init(status:http.statusCode,body:data,retryAfter:Self.retryAfter(http.value(forHTTPHeaderField:"Retry-After")))
    }
    static func retryAfter(_ value:String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds=TimeInterval(value),seconds.isFinite,seconds>=0 { return seconds }
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX"); formatter.timeZone=TimeZone(secondsFromGMT:0)
        formatter.dateFormat="EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from:value).map{max(0,$0.timeIntervalSinceNow)}
    }
}

/// Disabled until the app applies the user's explicit preference. Keys never enter
/// AppSettings, SQLite, URLs, exports, logs or source files. At most two delayed
/// retries for explicit temporary server failures; no retries for quota or keys.
public actor GoogleAIClient {
    public static let defaultModel="gemini-3.8-flash"
    private let credentials:any GoogleAICredentialStore
    private let transport:any GoogleAITransport
    private let retryPause:@Sendable (Duration) async throws -> Void
    private var enabled=false
    private var authorizationRevision=0
    private var active:Task<GoogleAIHTTPReply,any Error>?
    public private(set) var retryStatus:String?
    public init(keychainService:String="local.audio.intelligence.google-ai") { credentials=GoogleAIKeychain(service:keychainService); transport=GoogleAIURLTransport(); retryPause={ try await Task.sleep(for:$0) } }
    init(credentials:any GoogleAICredentialStore,transport:any GoogleAITransport,retryPause:@escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for:$0) }) {
        self.credentials=credentials; self.transport=transport; self.retryPause=retryPause
    }
    public func setEnabled(_ value:Bool) { authorizationRevision += 1; enabled=value; if !value { active?.cancel() } }
    public func saveKey(_ value:String) async throws {
        let value=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty,value.count<=512,!value.contains(where:{$0.isNewline}) else { throw GoogleAIError.missingKey }
        authorizationRevision += 1; active?.cancel()
        try await credentials.save(value)
    }
    public func deleteKey() async throws { authorizationRevision += 1; active?.cancel(); try await credentials.delete() }
    public func hasKey() async throws -> Bool { try await credentials.read()?.isEmpty==false }
    public static func normalizedModel(_ model:String) throws -> String {
        let model=model.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"models/",with:"")
        guard model.range(of:"^gemini-[A-Za-z0-9][A-Za-z0-9._-]{0,90}$",options:.regularExpression) != nil else { throw GoogleAIError.invalidModel }
        return model
    }
    public func availability(model:String) async -> String? {
        do {
            guard enabled else { throw GoogleAIError.disabled }
            _=try Self.normalizedModel(model)
            guard try await hasKey() else { throw GoogleAIError.missingKey }
            return nil
        } catch { return error.localizedDescription }
    }
    private func request(model:String,generate:Bool,body:Data?=nil) async throws -> URLRequest {
        guard enabled else { throw GoogleAIError.disabled }
        let revision=authorizationRevision
        let model=try Self.normalizedModel(model)
        guard let key=try await credentials.read(),!key.isEmpty else { throw GoogleAIError.missingKey }
        guard enabled else { throw GoogleAIError.disabled }
        guard revision==authorizationRevision else { throw GoogleAIError.configurationChanged }
        let url=URL(string:"https://generativelanguage.googleapis.com/v1beta/models/"+model+(generate ? ":generateContent":""))!
        var request=URLRequest(url:url,timeoutInterval:90)
        request.httpMethod=generate ? "POST":"GET"; request.httpBody=body
        request.setValue(key,forHTTPHeaderField:"x-goog-api-key")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        return request
    }
    private func send(_ request:URLRequest) async throws -> Data {
        guard enabled else { throw GoogleAIError.disabled }
        guard active==nil else { throw GoogleAIError.busy }
        let revision=authorizationRevision
        let task=Task {
            for attempt in 0...2 {
                try Task.checkCancellation()
                guard enabled else { throw GoogleAIError.disabled }
                guard revision==authorizationRevision else { throw GoogleAIError.configurationChanged }
                if attempt>0 { retryStatus="Reintentando Google AI · intento \(attempt+1) de 3…" }
                let reply=try await transport.send(request,maximumBytes:256*1024)
                guard [500,502,503,504].contains(reply.status),attempt<2 else { return reply }
                // Respect a long Retry-After by stopping instead of retrying early.
                guard (reply.retryAfter ?? 0)<=30 else { return reply }
                let delay=max(Double(2 << attempt),reply.retryAfter ?? 0)+Double.random(in:0...0.5)
                retryStatus="Google AI no disponible · reintento \(attempt+1) de 2 en \(Int(delay.rounded(.up))) s…"
                try await retryPause(.milliseconds(Int64(delay*1000)))
            }
            throw GoogleAIError.http(503)
        }
        active=task; defer { active=nil; retryStatus=nil }
        do {
            let reply=try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard enabled else { throw GoogleAIError.disabled }
            guard (200..<300).contains(reply.status) else { throw GoogleAIError.http(reply.status) }
            guard reply.body.count<=256*1024 else { throw GoogleAIError.responseTooLarge }
            return reply.body
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? GoogleAIError.timeout:GoogleAIError.offline
        }
    }
    public func testConnection(model:String) async throws -> String {
        let request=try await request(model:model,generate:false)
        let data=try await send(request)
        struct Model:Decodable { var displayName:String?; var supportedGenerationMethods:[String]? }
        guard let result=try? JSONDecoder().decode(Model.self,from:data),result.supportedGenerationMethods?.contains("generateContent")==true else { throw GoogleAIError.invalidModel }
        return result.displayName ?? model
    }
    func generate(model:String,instructions:String,prompt:String,schema:Data) async throws -> Data {
        let schema=try JSONSerialization.jsonObject(with:schema)
        let payload:[String:Any]=[
            "systemInstruction":["parts":[["text":instructions]]],
            "contents":[["role":"user","parts":[["text":prompt]]]],
            "generationConfig":["candidateCount":1,"maxOutputTokens":4096,
                "responseFormat":["text":["mimeType":"APPLICATION_JSON","schema":schema]]]
        ]
        let body=try JSONSerialization.data(withJSONObject:payload)
        guard body.count<=96*1024 else { throw SummaryContextError.exceeded }
        let request=try await request(model:model,generate:true,body:body)
        return try Self.decodeContent(try await send(request))
    }
    static func decodeContent(_ data:Data) throws -> Data {
        struct Envelope:Decodable {
            struct Part:Decodable { var text:String?; var thought:Bool? }
            struct Content:Decodable { var parts:[Part]? }
            struct Candidate:Decodable { var content:Content?; var finishReason:String? }
            struct Feedback:Decodable { var blockReason:String? }
            var candidates:[Candidate]?; var promptFeedback:Feedback?
        }
        guard let response=try? JSONDecoder().decode(Envelope.self,from:data) else { throw GoogleAIError.incomplete }
        if response.promptFeedback?.blockReason != nil { throw GoogleAIError.blocked }
        guard let candidate=response.candidates?.first else { throw GoogleAIError.blocked }
        guard candidate.finishReason=="STOP" else { throw GoogleAIError.incomplete }
        let text=(candidate.content?.parts ?? []).filter{$0.thought != true}.compactMap(\.text).joined()
        guard !text.isEmpty else { throw GoogleAIError.incomplete }
        return Data(text.utf8)
    }
}
