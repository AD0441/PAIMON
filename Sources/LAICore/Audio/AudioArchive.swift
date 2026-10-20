import Foundation
import AVFoundation
public actor AudioArchive {
    private var files:[AudioSource:AVAudioFile]=[:]
    private let directory:URL
    public init(directory:URL) { self.directory=directory }
    public func append(_ chunk:AudioChunk) throws {
        if files[chunk.source]==nil {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            // A separate file per source; timing is recorded incrementally alongside PCM.
            let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:chunk.sampleRate,channels:1,interleaved:false)!
            files[chunk.source]=try AVAudioFile(forWriting:directory.appendingPathComponent(chunk.source.rawValue+".caf"),settings:format.settings)
        }
        let file=files[chunk.source]!
        let position=file.framePosition
        try file.write(from:PCMConverter.buffer(chunk,format:file.processingFormat))
        let url=directory.appendingPathComponent("timing.jsonl")
        if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.posixPermissions:0o600]) }
        let handle=try FileHandle(forWritingTo:url); defer { try? handle.close() }; try handle.seekToEnd()
        let record=try JSONSerialization.data(withJSONObject:["source":chunk.source.rawValue,"start":chunk.start,"frame":position,"frames":chunk.samples.count,"sampleRate":chunk.sampleRate])
        try handle.write(contentsOf:record+Data([10]))
    }
    public func close() { files.removeAll() }
}
