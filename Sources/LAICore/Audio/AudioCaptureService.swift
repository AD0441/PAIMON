import Foundation
import CoreAudio
import AVFoundation
import AudioRing

// Safety invariant: C owns atomics and preallocated storage; one callback writes and
// one AudioCaptureService actor reads. Stop/destroy callbacks before releasing rings.
// Remove unchecked conformance if Core Audio gains a Sendable callback context type.
final class AudioRingHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init() throws { guard let p=lai_ring_create() else { throw LAIError.message("No hay memoria para audio") }; pointer=p }
    deinit { lai_ring_destroy(pointer) }
}
public struct AudioDeviceChoice: Identifiable, Sendable, Hashable {
    public var id: UInt32; public var name: String; public var uid: String
}
public enum AudioHardware {
    static func check(_ status: OSStatus, _ operation: String) throws { if status != noErr { throw LAIError.message("\(operation): Core Audio \(status). Comprueba Privacidad y seguridad → Grabación de audio del sistema.") } }
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress { .init(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain) }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a=address(selector); var value:Unmanaged<CFString>?; var size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object,&a,0,nil,&size,&value)==noErr else { return "" }; return value?.takeRetainedValue() as String? ?? ""
    }
    public static func devices(input: Bool) -> [AudioDeviceChoice] {
        var a=address(kAudioHardwarePropertyDevices); var size:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size)==noErr else { return [] }
        var ids=[AudioObjectID](repeating:0,count:Int(size)/4)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&ids)==noErr else { return [] }
        return ids.compactMap { id in
            var streams=address(kAudioDevicePropertyStreams,scope:input ? kAudioDevicePropertyScopeInput:kAudioDevicePropertyScopeOutput); var bytes:UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&bytes)==noErr,bytes>0 else { return nil }
            return .init(id:id,name:string(id,kAudioObjectPropertyName),uid:string(id,kAudioDevicePropertyDeviceUID))
        }
    }
}
public struct CaptureDiagnostics: Codable, Sendable {
    public var buffers:UInt64=0
    public var frames:UInt64=0
    public var nonzeroBuffers:UInt64=0
    public init() {}
}
public actor AudioCaptureService {
    private var tap: AudioObjectID=0
    private var aggregate: AudioObjectID=0
    private var io: AudioDeviceIOProcID?
    private var systemRing: AudioRingHandle?
    private var microphoneRing: AudioRingHandle?
    private var systemRate: Double=48000
    private var micRate: Double=48000
    private var engine: AVAudioEngine?
    private var epoch: Double=0
    private var diagnostics=CaptureDiagnostics()
    public init() {}
    public func start(settings: AppSettings, epoch: Double) async throws {
        if self.epoch != epoch { diagnostics=CaptureDiagnostics() }
        self.epoch=epoch
        do {
            if settings.microphone {
                let granted=await AVCaptureDevice.requestAccess(for:.audio)
                guard granted else { throw LAIError.message("Permiso de micrófono denegado. Actívalo en Ajustes del Sistema.") }
                try startMicrophone(device:settings.microphoneDevice)
            }
            if settings.systemAudio { try startSystem(settings:settings) }
        } catch { _=stop(); throw error }
    }
    private func startSystem(settings: AppSettings) throws {
        let description=CATapDescription(stereoGlobalTapButExcludeProcesses:[])
        description.name="PAIMON"
        description.isPrivate=true
        description.muteBehavior = .unmuted
        description.isProcessRestoreEnabled=true
        if !settings.applicationBundleID.isEmpty { description.isExclusive=false; description.bundleIDs=[settings.applicationBundleID] }
        else { description.bundleIDs=[Bundle.main.bundleIdentifier ?? "local.audio.intelligence"] }
        if !settings.outputDeviceUID.isEmpty { description.deviceUID=settings.outputDeviceUID; description.stream=0 }
        try AudioHardware.check(AudioHardwareCreateProcessTap(description,&tap),"Crear tap")
        var a=AudioHardware.address(kAudioTapPropertyFormat)
        var format=AudioStreamBasicDescription(); var size=UInt32(MemoryLayout.size(ofValue:format))
        try AudioHardware.check(AudioObjectGetPropertyData(tap,&a,0,nil,&size,&format),"Formato del tap")
        guard format.mSampleRate>0, format.mFormatID==kAudioFormatLinearPCM,
              (format.mBitsPerChannel==32 && format.mFormatFlags & kAudioFormatFlagIsFloat != 0) || (format.mBitsPerChannel==16 && format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0) else { throw LAIError.message("Formato de audio del tap no compatible") }
        systemRate=format.mSampleRate
        let config:[String:Any]=[
            kAudioAggregateDeviceNameKey:"PAIMON Capture",
            kAudioAggregateDeviceUIDKey:UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey:true,
            kAudioAggregateDeviceTapAutoStartKey:true,
            kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:description.uuid.uuidString,kAudioSubTapDriftCompensationKey:true]]]
        try AudioHardware.check(AudioHardwareCreateAggregateDevice(config as CFDictionary,&aggregate),"Crear dispositivo agregado")
        let ring=try AudioRingHandle(); systemRing=ring
        let callbackFormat=format
        try AudioHardware.check(AudioDeviceCreateIOProcIDWithBlock(&io,aggregate,nil) { _,data,time,_,_ in
            var f=callbackFormat
            lai_ring_push(ring.pointer,data,&f,time.pointee.mHostTime)
        },"Crear callback")
        try AudioHardware.check(AudioDeviceStart(aggregate,io),"Iniciar tap")
    }
    private func startMicrophone(device: UInt32) throws {
        let audio=AVAudioEngine(); let input=audio.inputNode
        if device != 0, let unit=input.audioUnit {
            var selected=device
            try AudioHardware.check(AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&selected,UInt32(MemoryLayout.size(ofValue:selected))),"Seleccionar micrófono")
        }
        let format=input.outputFormat(forBus:0)
        guard format.sampleRate>0,format.channelCount>0 else { throw LAIError.message("No hay micrófono disponible") }
        let ring=try AudioRingHandle(); microphoneRing=ring; micRate=format.sampleRate
        input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,time in
            var f=buffer.format.streamDescription.pointee
            lai_ring_push(ring.pointer,buffer.audioBufferList,&f,time.hostTime)
        }
        // Never connect the input to an output node: no monitoring / feedback loop.
        engine=audio; try audio.start()
    }
    public func captureDiagnostics() -> CaptureDiagnostics { diagnostics }
    // Permission dialogs and device startup may take arbitrarily long. Start the
    // session clock only once all sources are ready; discard their bounded preroll.
    public func beginTimeline() -> Double {
        _=drain()
        epoch=ProcessInfo.processInfo.systemUptime
        diagnostics=CaptureDiagnostics()
        return epoch
    }
    public func drain() -> [AudioChunk] {
        var output:[AudioChunk]=[]
        for (source,ring,rate) in [(AudioSource.system,systemRing,systemRate),(.microphone,microphoneRing,micRate)] {
            guard let ring else { continue }
            var samples=[Float](repeating:0,count:Int(lai_ring_max_frames())); var time:UInt64=0
            for _ in 0..<64 {
                let count=lai_ring_pop(ring.pointer,&samples,UInt32(samples.count),&time)
                if count==0 { break }
                diagnostics.buffers += 1; diagnostics.frames += UInt64(count)
                if samples.prefix(Int(count)).contains(where:{abs($0)>0.001}) { diagnostics.nonzeroBuffers += 1 }
                let start=max(0,AVAudioTime.seconds(forHostTime:time)-epoch)
                output.append(.init(samples:Array(samples.prefix(Int(count))),sampleRate:rate,start:start,source:source))
            }
        }
        return output.sorted { $0.start < $1.start }
    }
    public func droppedBuffers() -> UInt64 { [systemRing,microphoneRing].compactMap{$0}.reduce(0){ $0+lai_ring_dropped($1.pointer) } }
    @discardableResult public func stop() -> [AudioChunk] {
        if aggregate != 0, let io { AudioDeviceStop(aggregate,io); AudioDeviceDestroyIOProcID(aggregate,io) }
        io=nil
        engine?.stop(); engine?.inputNode.removeTap(onBus:0); engine=nil
        let remaining=drain()
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate=0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap=0 }
        systemRing=nil; microphoneRing=nil
        return remaining
    }
}
