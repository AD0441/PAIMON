import Foundation
import CoreML
import FluidAudio
import Darwin
@main struct FluidWorker {
    static func main() async {
        let descriptor=dup(STDOUT_FILENO)
        dup2(STDERR_FILENO,STDOUT_FILENO)
        let channel=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)
        do {
            if CommandLine.arguments.count==3,CommandLine.arguments[1]=="--diarize" {
                try diarize(directory:URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true),channel:channel)
                return
            }
            guard CommandLine.arguments.count==2 else { throw NSError(domain:"FluidWorker",code:1,userInfo:[NSLocalizedDescriptionKey:"Expected local model directory"]) }
            let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
            let configuration=AsrModels.defaultConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            // loadLocal fails on absent files; it NEVER calls download helpers.
            let models=try AsrModels.loadLocal(from:directory,version:.redux,configuration:configuration)
            let manager=AsrManager(config:.default); try await manager.loadModels(models)
            while let line=readLine() {
                do {
                    let request=try JSONDecoder().decode(Request.self,from:Data(line.utf8))
                    let samples=try request.samples(limit:240_000)
                    var state=try TdtDecoderState()
                    let result=try await manager.transcribe(samples,decoderState:&state)
                    let reply=try JSONSerialization.data(withJSONObject:["text":result.text])
                    try channel.write(contentsOf:reply+Data([10]))
                } catch { try channel.write(contentsOf:JSONSerialization.data(withJSONObject:["error":error.localizedDescription])+Data([10])) }
            }
        } catch { try? channel.write(contentsOf:JSONSerialization.data(withJSONObject:["error":error.localizedDescription])+Data([10])) }
    }

    private struct Request: Decodable {
        let pcm: Data
        let source: String?

        func samples(limit: Int) throws -> [Float] {
            guard !pcm.isEmpty,pcm.count.isMultiple(of:4),pcm.count<=limit*4 else {
                throw NSError(domain:"FluidWorker",code:2,userInfo:[NSLocalizedDescriptionKey:"Invalid PCM window"])
            }
            return pcm.withUnsafeBytes { bytes in
                stride(from:0,to:bytes.count,by:4).map { bytes.loadUnaligned(fromByteOffset:$0,as:Float.self) }
            }
        }
    }

    private static func diarize(directory:URL,channel:FileHandle) throws {
        let segmentation=directory.appendingPathComponent("pyannote_segmentation.mlmodelc")
        let embedding=directory.appendingPathComponent("wespeaker_v2.mlmodelc")
        // Read a request before loading so startup errors can use the same
        // request/reply channel and the caller never writes to an exited child.
        var models:DiarizerModels?
        var managers:[String:DiarizerManager]=[:]
        while let line=readLine() {
            do {
                let request=try JSONDecoder().decode(Request.self,from:Data(line.utf8))
                guard let source=request.source,["system","microphone","file"].contains(source) else {
                    throw NSError(domain:"FluidWorker",code:3,userInfo:[NSLocalizedDescriptionKey:"Invalid diarization audio source"])
                }
                let manager:DiarizerManager
                if let existing=managers[source] {
                    manager=existing
                } else {
                    let configuration=MLModelConfiguration()
                    configuration.computeUnits = .cpuAndNeuralEngine
                    let loaded=try models ?? DiarizerModels.load(localSegmentationModel:segmentation,localEmbeddingModel:embedding,configuration:configuration)
                    models=loaded
                    manager=DiarizerManager()
                    manager.initialize(models:loaded)
                    managers[source]=manager
                }
                let samples=try request.samples(limit:160_000)
                let result=try manager.performCompleteDiarization(samples)
                let turns=result.segments.map { segment -> [String:Any] in
                    ["speaker":segment.speakerId,"start":Double(segment.startTimeSeconds),"end":Double(segment.endTimeSeconds)]
                }
                try channel.write(contentsOf:JSONSerialization.data(withJSONObject:["turns":turns])+Data([10]))
            } catch {
                try channel.write(contentsOf:JSONSerialization.data(withJSONObject:["error":error.localizedDescription])+Data([10]))
                return
            }
        }
    }
}
