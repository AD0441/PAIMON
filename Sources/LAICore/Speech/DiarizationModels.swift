import CryptoKit
import Foundation

public enum DiarizationModels {
    // Only these exact files are fetched. Git LFS objects have SHA-256
    // digests. Small files stored directly in Git use their blob IDs.
    static let revision = "7eab74f3463c736418d0eb10296261ae581146c9"
    private static let source = URL(string:"https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve")!
    private static let managedName = "Diarization-\(revision.prefix(7))"
    private static let modelNames = ["pyannote_segmentation.mlmodelc","wespeaker_v2.mlmodelc"]

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

    private static let assets = [
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

    public static var directory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("PAIMON Models",isDirectory:true)
            .appendingPathComponent(managedName,isDirectory:true)
    }

    public static var installed: Bool { containsModels(at:directory) }

    public static func containsModels(at folder: URL) -> Bool {
        modelNames.allSatisfy {
            FileManager.default.fileExists(atPath:folder.appendingPathComponent($0+"/model.mil").path)
        }
    }

    public static func workerPath(configured: String) -> String? {
        let bundled=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/FluidWorker").path
        return [bundled,configured].first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath:$0) }
    }

    @concurrent public static func download(progress: @Sendable (Double) async -> Void) async throws -> URL {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies=false
        configuration.urlCredentialStorage=nil
        configuration.timeoutIntervalForRequest=30
        configuration.timeoutIntervalForResource=120
        let session=URLSession(configuration:configuration)
        defer { session.finishTasksAndInvalidate() }
        return try await install(at:directory,assets:assets,fetch:{ url in
            let (file,response)=try await session.download(from:url)
            guard let http=response as? HTTPURLResponse,http.statusCode==200 else {
                try? FileManager.default.removeItem(at:file)
                throw LAIError.message("Hugging Face no pudo entregar los modelos (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            return file
        },progress:progress)
    }

    public static func remove() throws {
        if FileManager.default.fileExists(atPath:directory.path) {
            try FileManager.default.removeItem(at:directory)
        }
    }

    static func install(at destination: URL, assets: [Asset], fetch: @Sendable (URL) async throws -> URL,
                        progress: @Sendable (Double) async -> Void) async throws -> URL {
        let manager=FileManager.default
        if assets.allSatisfy({ (try? verify(destination.appendingPathComponent($0.path),asset:$0))==true }) {
            await progress(1)
            return destination
        }

        let staging=destination.deletingLastPathComponent().appendingPathComponent(".paimon-download-\(UUID().uuidString)",isDirectory:true)
        try manager.createDirectory(at:staging,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? manager.removeItem(at:staging) }
        let model=staging.appendingPathComponent("model",isDirectory:true)
        let total=Double(assets.reduce(0) { $0+$1.bytes })
        var received=0
        for asset in assets {
            try Task.checkCancellation()
            let url=source.appendingPathComponent(revision).appendingPathComponent(asset.path)
            let file=try await fetch(url)
            defer { try? manager.removeItem(at:file) }
            try Task.checkCancellation()
            guard try verify(file,asset:asset) else {
                throw LAIError.message("No se pudo verificar el archivo descargado. Vuelve a intentar la descarga.")
            }
            let target=model.appendingPathComponent(asset.path)
            try manager.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try manager.moveItem(at:file,to:target)
            received+=asset.bytes
            await progress(Double(received)/total)
        }

        try Task.checkCancellation()
        if manager.fileExists(atPath:destination.path) {
            _=try manager.replaceItemAt(destination,withItemAt:model)
        } else {
            try manager.moveItem(at:model,to:destination)
        }
        return destination
    }

    private static func verify(_ url: URL, asset: Asset) throws -> Bool {
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize
        guard size==asset.bytes else { return false }
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        let digest:String
        if asset.digest.count==40 {
            var hash=Insecure.SHA1()
            hash.update(data:Data("blob \(asset.bytes)\0".utf8))
            hash.update(data:data)
            digest=hash.finalize().map { String(format:"%02x",$0) }.joined()
        } else {
            digest=SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        }
        return digest==asset.digest
    }
}
