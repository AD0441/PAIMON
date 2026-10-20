import Foundation
import Darwin
// Blocking pipe IO is isolated to this actor, never used from UI / capture callbacks.
// The child has no network API in the request protocol. Only configured local files.
public actor LocalWorker {
    private var process:Process?
    private var input:FileHandle?
    private var output:FileHandle?
    public init() {}
    public func start(executable: String, arguments: [String]) throws {
        guard process==nil,FileManager.default.isExecutableFile(atPath:executable) else { throw LAIError.message("No se encuentra el ejecutable local: \(executable)") }
        let p=Process(); p.executableURL=URL(fileURLWithPath:executable); p.arguments=arguments
        var environment=ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"]="1"; environment["TRANSFORMERS_OFFLINE"]="1"; environment["TOKENIZERS_PARALLELISM"]="false"
        p.environment=environment
        let stdin=Pipe(); let stdout=Pipe(); p.standardInput=stdin; p.standardOutput=stdout
        // Inherit stderr; child logs cannot corrupt the line-delimited JSON channel.
        try p.run(); process=p; input=stdin.fileHandleForWriting; output=stdout.fileHandleForReading
    }
    public func request(_ data: Data) throws -> Data {
        guard let process,process.isRunning,let input,let output else { throw LAIError.message("El motor local no está iniciado") }
        let pid=process.processIdentifier
        let watchdog=DispatchWorkItem { kill(pid,SIGKILL) }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+180,execute:watchdog)
        defer { watchdog.cancel() }
        try input.write(contentsOf:data+Data([10]))
        var line=Data()
        while let byte=try output.read(upToCount:1),!byte.isEmpty {
            if byte[0]==10 { return line }
            line.append(byte)
            if line.count>2_000_000 { throw LAIError.message("Respuesta del motor demasiado grande") }
        }
        throw LAIError.message("El motor local terminó antes de responder")
    }
    public func stop() {
        try? input?.close(); try? output?.close(); if let process,process.isRunning { process.terminate(); process.waitUntilExit() }
        input=nil; output=nil; process=nil
    }
}
