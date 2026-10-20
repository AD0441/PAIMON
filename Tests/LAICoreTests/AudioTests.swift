import Foundation
import Testing
import AVFoundation
import AudioRing
@testable import LAICore
@Test func ringBoundedOverflowDownmixAndRecovery() throws {
    let ring=try #require(lai_ring_create()); defer { lai_ring_destroy(ring) }
    var format=AudioStreamBasicDescription(mSampleRate:48000,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,mBytesPerPacket:8,mFramesPerPacket:1,mBytesPerFrame:8,mChannelsPerFrame:2,mBitsPerChannel:32,mReserved:0)
    var samples:[Float]=[1,0,0.5,0.5,-1,1]
    samples.withUnsafeMutableBytes { data in
        var list=AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:2,mDataByteSize:UInt32(data.count),mData:data.baseAddress))
        for i in 0..<70 { lai_ring_push(ring,&list,&format,UInt64(i)) }
    }
    #expect(lai_ring_dropped(ring)==6)
    var output=[Float](repeating:0,count:8192); var time:UInt64=0
    for i in 0..<64 {
        #expect(lai_ring_pop(ring,&output,UInt32(output.count),&time)==3); #expect(time==UInt64(i)); #expect(output[0]==0.5); #expect(output[1]==0.5); #expect(output[2]==0)
    }
    #expect(lai_ring_pop(ring,&output,UInt32(output.count),&time)==0)
}
@Test func vadHysteresisAndPCMConversion() throws {
    var detector=VAD()
    #expect(detector.process([Float](repeating:0.1,count:1600),sampleRate:16000).1)
    #expect(detector.process([Float](repeating:0,count:1600),sampleRate:16000).1)
    #expect(!detector.process([Float](repeating:0,count:16000),sampleRate:16000).1)
    let chunk=AudioChunk(samples:(0..<4800).map{sin(Float($0)*0.02)},sampleRate:48000,start:0,source:.system)
    let format=try #require(AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false))
    let converted=try PCMConverter.buffer(chunk,format:format)
    #expect(converted.frameLength>1400 && converted.frameLength<=1664, "Converted frames: \(converted.frameLength)")
    #expect(converted.format.sampleRate==16000)
}
@Test func continuousConverterPreservesSamples() throws {
    let target=try #require(AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:false))
    let converter=PCMStreamConverter()
    var total=0
    for index in 0..<10 {
        let chunk=AudioChunk(samples:[Float](repeating:0.1,count:4096),sampleRate:22050,start:Double(index*4096)/22050,source:.system)
        total += Int(try converter.buffer(chunk,format:target).frameLength)
    }
    #expect(abs(total-29721)<150,"Continuous output frames: \(total)")
}
