import Foundation
import LAICore

/// Explicit CLI diagnostic using synthetic text and a temporary database, never user sessions.
func benchmarkSessionTools(output:URL) async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Benchmark local",settings:AppSettings()); try await store.save(session)
    let before=ResourceMetrics.current()
    func write(_ range:Range<Int>) async throws -> [Double] {
        var times:[Double]=[]
        for i in range {
            let segment=TranscriptSegment(sessionID:session.id,source:.system,start:Double(i*5),end:Double(i*5+5),text:"Concepto \(i): la energía eléctrica se transforma. Revisamos el presupuesto y las condiciones del laboratorio. La información pertenece a una muestra sintética de rendimiento.")
            let start=DispatchTime.now().uptimeNanoseconds
            try await store.append(segment)
            times.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000)
        }
        return times
    }
    let writes=try await write(0..<1000)
    func search() async throws -> [Double] {
        var times:[Double]=[]
        for i in 0..<200 {
            let start=DispatchTime.now().uptimeNanoseconds
            _=try await store.searchTranscripts(i%2==0 ? "energia electri":"presup")
            times.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000)
        }
        return times
    }
    async let searches=search()
    async let concurrentWrites=write(1000..<1200)
    let pair=try await (searches,concurrentWrites)
    func stats(_ values:[Double]) -> [String:Double] {
        let sorted=values.sorted()
        return ["p50ms":sorted[sorted.count/2],"p95ms":sorted[Int(Double(sorted.count-1)*0.95)],"maxMs":sorted.last!]
    }
    let after=ResourceMetrics.current()
    let report:[String:Any]=["fixtureSegments":1200,"queriesDuringWrites":200,"resultLimit":50,"indexedWrites":stats(writes),"writesWithSearch":stats(pair.1),"queriesWithWrites":stats(pair.0),"clientFootprintBeforeMB":before.footprintMB,"clientFootprintAfterMB":after.footprintMB,"note":"Synthetic SQLite benchmark. No audio or language models loaded; not an Instruments or battery measurement."]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
    print("PASS: 1200 indexed segments, 200 searches concurrent with incremental writes. Report: \(output.path)")
}
