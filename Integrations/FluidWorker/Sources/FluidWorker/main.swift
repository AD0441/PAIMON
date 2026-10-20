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
            guard CommandLine.arguments.count==2 else { throw NSError(domain:"FluidWorker",code:1,userInfo:[NSLocalizedDescriptionKey:"Expected local model directory"]) }
            let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
            let configuration=AsrModels.defaultConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            // loadLocal fails on absent files; it NEVER calls download helpers.
            let models=try AsrModels.loadLocal(from:directory,version:.redux,configuration:configuration)
            let manager=AsrManager(config:.default); try await manager.loadModels(models)
            while let line=readLine() {
                do {
                    guard let json=try JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:String],let encoded=json["pcm"],let pcm=Data(base64Encoded:encoded),pcm.count%4==0 else { throw NSError(domain:"FluidWorker",code:2) }
                    let samples=pcm.withUnsafeBytes { bytes -> [Float] in
                        stride(from:0,to:bytes.count,by:4).map { offset in bytes.loadUnaligned(fromByteOffset:offset,as:Float.self) }
                    }
                    guard samples.count<=240000 else { throw NSError(domain:"FluidWorker",code:3) }
                    var state=try TdtDecoderState()
                    let result=try await manager.transcribe(samples,decoderState:&state)
                    let reply=try JSONSerialization.data(withJSONObject:["text":result.text])
                    try channel.write(contentsOf:reply+Data([10]))
                } catch { try channel.write(contentsOf:JSONSerialization.data(withJSONObject:["error":error.localizedDescription])+Data([10])) }
            }
        } catch { try? channel.write(contentsOf:JSONSerialization.data(withJSONObject:["error":error.localizedDescription])+Data([10])) }
    }
}
