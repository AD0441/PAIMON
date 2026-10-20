import Foundation
import LAICore
import Speech
@main struct LAICheck {
    static func main() async {
        do {
            let arguments=Array(CommandLine.arguments.dropFirst())
            if arguments.first=="--benchmark-long-sessions",arguments.count>=2 {
                try await benchmarkLongSessions(output:URL(fileURLWithPath:arguments[1]))
            } else if arguments.first=="--benchmark-tools",arguments.count>=2 {
                try await benchmarkSessionTools(output:URL(fileURLWithPath:arguments[1]))
            } else if arguments.first=="--validate-summary",arguments.count>=2 {
                try await validateSummaryQuality(output:URL(fileURLWithPath:arguments[1]))
            } else if arguments.first=="--repair-summary",arguments.count>=3,let id=UUID(uuidString:arguments[1]) {
                try await repairSummary(id:id,output:URL(fileURLWithPath:arguments[2]))
            } else if arguments.first=="--transcribe",arguments.count>=2 {
                var settings=AppSettings(); if arguments.count>2 { settings.locale=arguments[2] }
                let pair=AsyncStream<PipelineEvent>.makeStream()
                let output=Task { @concurrent in
                    var count=0
                    for await event in pair.stream { if case .warning(let warning)=event { print("WARNING: \(warning)") }; if case .segment(let s)=event,s.isFinal { print("[\(timestamp(s.start))–\(timestamp(s.end))] \(s.text)"); count += 1 } }
                    return count
                }
                do { try await AudioFileTranscriber.transcribe(url:URL(fileURLWithPath:arguments[1]),settings:settings,sessionID:UUID(),events:pair.continuation) }
                catch { pair.continuation.finish(); _=await output.value; throw error }
                pair.continuation.finish(); let count=await output.value
                guard count>0 else { throw LAIError.message("No se produjo texto definitivo") }; print("PASS: \(count) segmentos reales")
            } else if arguments.first=="--summary" {
                let template=arguments.count>1 ? SummaryTemplate(rawValue:arguments[1]) ?? .meeting:.meeting
                let id=UUID()
                let text=template == .lecture ? "La corriente eléctrica es el movimiento de cargas. La intensidad se mide en amperios. La ley de Ohm relaciona el voltaje, la corriente y la resistencia: el voltaje es igual a la corriente por la resistencia.":"Hoy revisamos el presupuesto del laboratorio. Acordamos comprar dos micrófonos. Ana enviará la cotización el viernes. Falta decidir dónde instalar los equipos."
                let segment=TranscriptSegment(sessionID:id,source:.file,start:0,end:20,text:text)
                let findings=try await FoundationSummaryEngine(template:template).summarize(segments:[segment],previous:[],final:true,locale:"es-ES")
                for finding in findings { print("\(finding.kind.rawValue): \(finding.text) | \(finding.quote)") }
                guard !findings.isEmpty else { throw LAIError.message("Sin hallazgos") }; print("PASS: resumen nativo real con citas validadas")
            } else {
                print("Speech available: \(SpeechTranscriber.isAvailable)")
                print("Installed locales: \(await SpeechTranscriber.installedLocales.map(\.identifier))")
                print("Spanish: \(await AppleSpeechEngine.availability(locale:"es-ES") ?? "ready")")
                print("English: \(await AppleSpeechEngine.availability(locale:"en-US") ?? "ready")")
                print("Summary: \(await FoundationSummaryEngine().availability(locale:"es-ES") ?? "ready")")
                let m=ResourceMetrics.current(); print("RSS MB: \(m.residentMB), footprint MB: \(m.footprintMB)")
            }
        } catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
    }
}
