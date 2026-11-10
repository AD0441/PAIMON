import CryptoKit
import Foundation
import Synchronization

public enum OptionalModelPackage: String, CaseIterable, Sendable {
    case diarization, parakeet, mlx

    private var revision: String {
        switch self {
        case .diarization: "7eab74f3463c736418d0eb10296261ae581146c9"
        case .parakeet: "8c5ef97a29cd120dc76b354b3f22b7fec3b486f9"
        case .mlx: "8b403126fc14f14cfc99bb4cfa72ecbc129ea677"
        }
    }

    private var repository: String {
        switch self {
        case .diarization: "FluidInference/speaker-diarization-coreml"
        case .parakeet: "FluidInference/parakeet-redux-coreml"
        case .mlx: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        }
    }

    private var assets: [Asset] {
        switch self {
        case .diarization: Self.diarizationAssets
        case .parakeet: Self.parakeetAssets
        case .mlx: Self.mlxAssets
        }
    }

    public var directory: URL {
        let name: String
        switch self {
        case .diarization: name="Diarization"
        case .parakeet: name="Parakeet"
        case .mlx: name="MLX-Qwen"
        }
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("PAIMON Models",isDirectory:true)
            .appendingPathComponent("\(name)-\(revision.prefix(7))",isDirectory:true)
    }

    public var installed: Bool {
        assets.allSatisfy { asset in
            let size=try? directory.appendingPathComponent(asset.path).resourceValues(forKeys:[.fileSizeKey]).fileSize
            return size==asset.bytes
        } && (self != .mlx || ManagedMLXRuntime.isReady(in:directory))
    }

    public static func fluidWorker(configured: String) -> String? {
        let bundled=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/FluidWorker").path
        return [bundled,configured].first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath:$0) }
    }

    public func remove() throws {
        if FileManager.default.fileExists(atPath:directory.path) {
            try FileManager.default.removeItem(at:directory)
        }
    }

    @concurrent public func download(progress: @Sendable @escaping (Double) async -> Void) async throws -> URL {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies=false
        configuration.urlCredentialStorage=nil
        configuration.timeoutIntervalForRequest=45
        configuration.timeoutIntervalForResource=3_600
        let session=URLSession(configuration:configuration)
        defer { session.finishTasksAndInvalidate() }
        let files=assets
        let total=Double(files.reduce(0) { $0+$1.bytes })
        let fraction=self == .mlx ? 0.94 : 1.0
        return try await install(at:directory,assets:files,fetch:{ url,asset,completed in
            let delegate=TransferProgress { received in
                let value=Double(completed+min(Int(received),asset.bytes))/total*fraction
                Task { await progress(value) }
            }
            return try await Self.fetch(url,using:session,delegate:delegate)
        },prepare:{ model in
            if self == .mlx {
                try await ManagedMLXRuntime.prepare(in:model) { url in
                    try await Self.fetch(url,using:session)
                }
            }
        },ready:{ folder in
            self != .mlx || ManagedMLXRuntime.isReady(in:folder)
        },progress:{ await progress($0*fraction) })
    }

    private static func fetch(_ url: URL, using session: URLSession, delegate: (any URLSessionTaskDelegate)?=nil) async throws -> URL {
        let (file,response)=try await session.download(from:url,delegate:delegate)
        guard let http=response as? HTTPURLResponse,http.statusCode==200 else {
            try? FileManager.default.removeItem(at:file)
            throw LAIError.message("No se pudo descargar el modelo (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        return file
    }

    struct Asset: Sendable {
        let path: String
        let bytes: Int
        let digest: String

        init(_ path: String, _ bytes: Int, _ digest: String) {
            self.path=path
            self.bytes=bytes
            self.digest=digest
        }
    }

    func install(at destination: URL, assets: [Asset],
                 fetch: @Sendable (URL,Asset,Int) async throws -> URL,
                 prepare: @Sendable (URL) async throws -> Void = { _ in },
                 ready: @Sendable (URL) -> Bool = { _ in true },
                 progress: @Sendable (Double) async -> Void) async throws -> URL {
        let manager=FileManager.default
        if ready(destination),assets.allSatisfy({ (try? Self.verify(destination.appendingPathComponent($0.path),asset:$0))==true }) {
            await progress(1)
            return destination
        }

        let staging=destination.deletingLastPathComponent().appendingPathComponent(".paimon-download-\(UUID().uuidString)",isDirectory:true)
        try manager.createDirectory(at:staging,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? manager.removeItem(at:staging) }
        let model=staging.appendingPathComponent("model",isDirectory:true)
        let base=URL(string:"https://huggingface.co/\(repository)/resolve/\(revision)")!
        let total=Double(assets.reduce(0) { $0+$1.bytes })
        var received=0
        for asset in assets {
            try Task.checkCancellation()
            let file=try await fetch(base.appendingPathComponent(asset.path),asset,received)
            defer { try? manager.removeItem(at:file) }
            try Task.checkCancellation()
            guard try Self.verify(file,asset:asset) else {
                throw LAIError.message("No se pudo verificar el archivo descargado. Vuelve a intentar la descarga.")
            }
            let target=model.appendingPathComponent(asset.path)
            try manager.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try manager.moveItem(at:file,to:target)
            received+=asset.bytes
            await progress(Double(received)/total)
        }

        try await prepare(model)
        try Task.checkCancellation()
        if manager.fileExists(atPath:destination.path) {
            _=try manager.replaceItemAt(destination,withItemAt:model)
        } else {
            try manager.moveItem(at:model,to:destination)
        }
        return destination
    }

    // Stream the hashes so even the largest weight file does not inflate RSS.
    static func verify(_ url: URL, asset: Asset) throws -> Bool {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize
        guard size==asset.bytes else { return false }
        let file=try FileHandle(forReadingFrom:url)
        defer { try? file.close() }
        if asset.digest.count==40 {
            var hash=Insecure.SHA1()
            hash.update(data:Data("blob \(asset.bytes)\0".utf8))
            try hashFile(file,into:&hash)
            return hex(hash.finalize())==asset.digest
        }
        var hash=SHA256()
        try hashFile(file,into:&hash)
        return hex(hash.finalize())==asset.digest
    }

    private static func hashFile<H:HashFunction>(_ file:FileHandle,into hash:inout H) throws {
        while let data=try file.read(upToCount:1024*1024),!data.isEmpty {
            try Task.checkCancellation()
            hash.update(data:data)
        }
    }

    private static func hex<D:Digest>(_ digest:D) -> String {
        digest.map { String(format:"%02x",$0) }.joined()
    }

    private static let diarizationAssets = [
        Asset("pyannote_segmentation.mlmodelc/analytics/coremldata.bin",243,"b379db0541b35344a34bb7540783ae704c11599bbed5aa8bbbda11c20ad215ee"),
        Asset("pyannote_segmentation.mlmodelc/coremldata.bin",316,"4a450ea1b053b9eb7eef0cab6971018076600840c7e246d064e7c5387f456c98"),
        Asset("pyannote_segmentation.mlmodelc/metadata.json",1763,"027a0a00cd4c1f69b8cc288b02d566b646ac6a52"),
        Asset("pyannote_segmentation.mlmodelc/model.mil",29490,"99db9c0b600166af69e06079df89f8ec91f527e9"),
        Asset("pyannote_segmentation.mlmodelc/weights/weight.bin",5734720,"0266f4ad4d843ecf31ef9220ad6b80616b3ec64a4404b64f3ea0371554e236ec"),
        Asset("wespeaker_v2.mlmodelc/analytics/coremldata.bin",243,"d2b1fcde6121aea3ff0e14c1dc50d09dacb0314a2e89156353c31804230a422f"),
        Asset("wespeaker_v2.mlmodelc/coremldata.bin",359,"6feb2472a71fa9d8a84020c85206138a4f6261c565c9884bf518d59dd5838da7"),
        Asset("wespeaker_v2.mlmodelc/metadata.json",2738,"5cda8cc14897fb37b01552a0fb9fefca31a6c00f"),
        Asset("wespeaker_v2.mlmodelc/model.mil",706900,"977dcf031d18b18fb5096d3e943ff8aa18754e21"),
        Asset("wespeaker_v2.mlmodelc/weights/weight.bin",7243904,"34004f6798d35cad7071e2fdc67e63faaa782f53697e1cb49bcb452cf81ae151"),
        Asset("LICENSE",19759,"176bb6930255c9859428728b4b5bdeb2ee40ae21"),
        Asset("NOTICE.md",4247,"1b6d5baabf814d90eec34902dee3ab512e522f6f")
    ]
    private static let parakeetAssets = [
        Asset("Decoder.mlmodelc/analytics/coremldata.bin",243,"7f24e7248d57024c6f1c5a2ea306f4a6a89db45a363218523bb6410c4b1aecf0"),
        Asset("Decoder.mlmodelc/coremldata.bin",560,"422da51d983e93a3e48cd6d46a17d6c32844452414c8e242fb0caaca2b8af5ed"),
        Asset("Decoder.mlmodelc/model.mil",13110,"36dcd5cbb71d13f42a177427ddbab7539e0d167e"),
        Asset("Decoder.mlmodelc/weights/weight.bin",23604992,"6c6c88c23ee5492a6b229e8cc636ddadb2b01ae0dd559d9cb63123bebf507d77"),
        Asset("Encoder.mlmodelc/analytics/coremldata.bin",243,"7862e972e09315df099d4bfd320743bf106acbf7fe4343317f9de45b0635d7b7"),
        Asset("Encoder.mlmodelc/coremldata.bin",506,"ca0b212fe3c06c3ccd35e508fa61e4dfaad19dd0c55b82e4f5bf8711e7758fd9"),
        Asset("Encoder.mlmodelc/model.mil",965906,"8328897b1fce282401724875571b75b6c542c4ed"),
        Asset("Encoder.mlmodelc/weights/weight.bin",182389312,"adbb5550dc6488717d3a1407b53122fbdb1af5e99c330ee20f8d8cfd9ec49252"),
        Asset("JointDecisionv3.mlmodelc/analytics/coremldata.bin",243,"fc857a756b8c9c9f31aa9e1062766cc0a82ac035ef369d6e1cbe97184921479c"),
        Asset("JointDecisionv3.mlmodelc/coremldata.bin",592,"611ea653e2adede7cc1cfe70da36296844f97e95e2c7dd961d45230e5599389d"),
        Asset("JointDecisionv3.mlmodelc/model.mil",11777,"be552d46f98f9dc9b242b0d1659833db60aa3f83"),
        Asset("JointDecisionv3.mlmodelc/weights/weight.bin",12642764,"73b0288acd115fc4c36038f66b6cbf49233182488febf5d8c787bea4009535f7"),
        Asset("Preprocessor.mlmodelc/analytics/coremldata.bin",243,"c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d"),
        Asset("Preprocessor.mlmodelc/coremldata.bin",486,"dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
        Asset("Preprocessor.mlmodelc/metadata.json",2841,"06162c58cf2f5343a0e60f36f843bcdf3cc58527"),
        Asset("Preprocessor.mlmodelc/model.mil",28181,"f987e2479228436c49189aa47edb376db74dcff5"),
        Asset("Preprocessor.mlmodelc/weights/weight.bin",491072,"129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
        Asset("README.md",4972,"9f4866223bf4bdc19b9260aaf0b6a93ebe6d88ee"),
        Asset("config.json",458,"1cc7d67913a2beddfaae005094a25171d0a3f18b"),
        Asset("parakeet_vocab.json",151122,"c684822ec3b671ebc449c433a7012398d39b8bb0")
    ]
    private static let mlxAssets = [
        Asset("README.md",748,"0a8005b4dede12c63ec8edfaa107c2e5af23cdef"),
        Asset("added_tokens.json",605,"482ced4679301bf287ebb310bdd1790eb4514232"),
        Asset("config.json",784,"d2741b5d6d48fa6f2ada841a2d6deb8a20137e5f"),
        Asset("merges.txt",1671853,"31349551d90c7606f325fe0f11bbb8bd5fa0d7c7"),
        Asset("model.safetensors",868628559,"0979f33d1bc58afcf696d13f57977644e7b11a6f0eec3e631d8e9463d18c0717"),
        Asset("model.safetensors.index.json",51569,"87eb58d416654c6c0ef987be30f6981a3176ffae"),
        Asset("special_tokens_map.json",613,"ac23c0aaa2434523c494330aeb79c58395378103"),
        Asset("tokenizer.json",7031673,"d24314ef7f0afd1b678c2e24c767e19f24f86b0e"),
        Asset("tokenizer_config.json",7308,"482ccbc1096b0e9400e86e33f189681c2aebdab9"),
        Asset("vocab.json",2776833,"4783fe10ac3adce15ac8f358ef5462739852c569")
    ]
}

private final class TransferProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    private let last=Mutex<Int64>(0)
    private let report: @Sendable (Int64) -> Void

    init(report: @escaping @Sendable (Int64) -> Void) { self.report=report }

    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        let changed=last.withLock { previous in
            guard totalBytesWritten-previous>=4*1024*1024 else { return false }
            previous=totalBytesWritten
            return true
        }
        if changed { report(totalBytesWritten) }
    }

    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {}
}
