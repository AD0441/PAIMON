import Foundation
import Darwin
public struct ResourceMetrics: Sendable {
    public var residentMB: Double
    public var footprintMB: Double
    public var cpuSeconds: Double
    public var thermal: Int
    public static func current() -> Self {
        var info=mach_task_basic_info(); var count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<natural_t>.size)
        let result=withUnsafeMutablePointer(to:&info) { p in p.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count) } }
        var vm=task_vm_info_data_t(); var vmCount=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/4)
        let vmResult=withUnsafeMutablePointer(to:&vm) { p in p.withMemoryRebound(to:integer_t.self,capacity:Int(vmCount)) { task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&vmCount) } }
        var usage=rusage(); getrusage(RUSAGE_SELF,&usage)
        let cpu=Double(usage.ru_utime.tv_sec+usage.ru_stime.tv_sec)+Double(usage.ru_utime.tv_usec+usage.ru_stime.tv_usec)/1_000_000
        return .init(residentMB:result==KERN_SUCCESS ? Double(info.resident_size)/1048576:0,footprintMB:vmResult==KERN_SUCCESS ? Double(vm.phys_footprint)/1048576:0,cpuSeconds:cpu,thermal:ProcessInfo.processInfo.thermalState.rawValue)
    }
}
