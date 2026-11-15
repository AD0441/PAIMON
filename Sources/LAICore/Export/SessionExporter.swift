import Foundation
public enum ExportFormat: String, CaseIterable, Sendable { case txt, markdown="md", pdf, json }
public struct ExportOptions: Sendable {
    public var transcript=true
    public var originalTranscript=false
    public var evidence=true
    public var bookmarks=true
    public var discourse=false
    public var kinds:Set<FindingKind>=Set(FindingKind.allCases)
    public init() {}
}
public actor SessionExporter {
    private struct EvidencePage:Codable { var findings:[Finding]; var referenceOffset:Int }
    private let store:SessionStore
    public init(store:SessionStore) { self.store=store }
    private func transcriptVariant(_ segment:TranscriptSegment,original:Bool) -> TranscriptSegment {
        guard original else { return segment }
        var value=segment
        value.text=segment.originalText ?? segment.text
        value.originalText=nil
        return value
    }
    public func export(session:Session,to url:URL,format:ExportFormat,options:ExportOptions) async throws {
        let revision=try await store.transcriptRevision(session:session.id)
        let discourseState=options.discourse ? try await store.discourseState(session:session.id):nil
        if let discourseState {
            let saved=try await store.session(id:session.id) ?? session
            guard discourseState.stamp==DiscourseAnalyzer.stamp(session:saved,revision:revision) else {
                throw LAIError.message("Actualiza el análisis de discurso antes de exportarlo.")
            }
        }
        if !options.kinds.isEmpty,try await store.summaryNeedsRefresh(session:session.id) {
            throw LAIError.message("Actualiza el resumen para incluir las correcciones.")
        }
        let workspace=try FileManager.default.url(for:.itemReplacementDirectory,in:.userDomainMask,
                                                  appropriateFor:url.deletingLastPathComponent(),create:true)
        defer { try? FileManager.default.removeItem(at:workspace) }
        let temp=workspace.appendingPathComponent("export.\(format.rawValue)")
        let evidenceFile:FileHandle?
        if options.evidence,format != .json,!options.kinds.isEmpty {
            let evidenceURL=workspace.appendingPathComponent("evidence.jsonl")
            guard FileManager.default.createFile(atPath:evidenceURL.path,contents:nil,attributes:[.posixPermissions:0o600]) else {
                throw LAIError.message("No se pudo preparar el anexo de evidencias.")
            }
            let file=try FileHandle(forUpdating:evidenceURL)
            // The open descriptor keeps the spool usable until close. Removing
            // its path now lets the OS reclaim it even if the app terminates.
            try FileManager.default.removeItem(at:evidenceURL)
            evidenceFile=file
        } else { evidenceFile=nil }
        defer { try? evidenceFile?.close() }
        func recordEvidence(_ report:SessionReport) throws {
            guard let evidenceFile,let first=report.evidence.first else { return }
            let page=EvidencePage(findings:report.evidence.map(\.finding),referenceOffset:first.reference-1)
            try evidenceFile.write(contentsOf:JSONEncoder().encode(page)); try evidenceFile.write(contentsOf:Data([10]))
        }
        while try await !store.indexNextFindingBatch(session:session.id) { try Task.checkCancellation(); await Task.yield() }
        let findings=try await store.latestSummary(session:session.id)?.findings.filter{options.kinds.contains($0.kind) && ($0.kind == .topic || $0.kind == .overview)} ?? []
        let encoder=JSONEncoder(); encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        let sections:[[FindingKind]]=[[.idea,.concept],[.decision],[.task],[.question],[.conclusion]]
        if format == .pdf {
            let writer=try PDFReportWriter(url:temp)
            let initial=SessionReportFormatter.document(session:session,findings:findings)
            try writer.report(initial,includeEvidence:options.evidence,includeEvidenceAnnex:false); try recordEvidence(initial)
            var references=initial.evidence.count
            for section in sections {
                let kinds=section.filter{options.kinds.contains($0)}; if kinds.isEmpty { continue }
                var offset=0
                while true {
                    try Task.checkCancellation()
                    let page=try await store.findings(session:session.id,template:session.template,kinds:kinds,limit:120,offset:offset)
                    if page.isEmpty { break }
                    let report=SessionReportFormatter.document(session:session,findings:page,referenceOffset:references)
                    try writer.report(report,includeEvidence:options.evidence,includeHeader:false,includeEvidenceAnnex:false); try recordEvidence(report)
                    references += report.evidence.count; offset += page.count
                }
            }
            if let evidenceFile {
                try evidenceFile.seek(toOffset:0)
                var firstEvidence=true
                for try await line in evidenceFile.bytes.lines {
                    try Task.checkCancellation()
                    let page=try JSONDecoder().decode(EvidencePage.self,from:Data(line.utf8))
                    try writer.evidence(SessionReportFormatter.document(session:session,findings:page.findings,referenceOffset:page.referenceOffset),first:firstEvidence)
                    firstEvidence=false
                }
            }
            if options.bookmarks {
                var offset=0
                while true {
                    let markers=try await store.bookmarks(session:session.id,offset:offset)
                    if markers.isEmpty { break }
                    try writer.bookmarks(markers,start:offset==0); offset += markers.count
                }
            }
            if options.transcript {
                try writer.startTranscript(original:options.originalTranscript)
                var cursor:Int64=0
                while true {
                    let rows=try await store.segments(session:session.id,after:cursor,limit:60)
                    if rows.isEmpty { break }
                    try writer.transcript(rows.map { transcriptVariant($0.1,original:options.originalTranscript) }); cursor=rows.last!.0
                }
            }
            if options.discourse {
                var offset=0
                repeat {
                    let page=try await store.discourseFindings(session:session.id,limit:100,offset:offset)
                    try writer.discourse(page,first:offset==0,includeEvidence:options.evidence)
                    offset += page.count
                    if page.count<100 { break }
                } while true
                try writer.participation(try await store.participation(session:session.id))
            }
            writer.close()
        } else {
            FileManager.default.createFile(atPath:temp.path,contents:nil,attributes:[.posixPermissions:0o600])
            let handle=try FileHandle(forWritingTo:temp); defer { try? handle.close() }
            func write(_ text:String) throws { try handle.write(contentsOf:Data(text.utf8)) }
            if format == .json {
                try write("{\"schemaVersion\":1,\"session\":")
                // Deliberately omit settings containing local executable/model paths.
                let metadata:[String:Any]=["id":session.id.uuidString,"title":session.title,"created":ISO8601DateFormatter().string(from:session.created),"duration":session.duration,"status":session.status,"template":session.template.rawValue,"transcriptVariant":options.originalTranscript ? "original":"current"]
                try handle.write(contentsOf:JSONSerialization.data(withJSONObject:metadata,options:[.sortedKeys]))
                try write(",\"findings\":[")
                var first=true
                for finding in findings { if !first { try write(",") }; try handle.write(contentsOf:encoder.encode(finding)); first=false }
                var offset=0
                while true {
                    try Task.checkCancellation()
                    let page=try await store.findings(session:session.id,template:session.template,limit:120,offset:offset)
                    if page.isEmpty { break }
                    for finding in page where options.kinds.contains(finding.kind) {
                        if !first { try write(",") }; try handle.write(contentsOf:encoder.encode(finding)); first=false
                    }
                    offset += page.count
                }
                try write("],\"bookmarks\":[")
            } else {
                let report=SessionReportFormatter.document(session:session,findings:findings)
                try write(format == .markdown ? SessionReportFormatter.markdown(report,includeEvidence:options.evidence,includeEvidenceAnnex:false):SessionReportFormatter.plainText(report,includeEvidence:options.evidence,includeEvidenceAnnex:false)); try recordEvidence(report)
                var references=report.evidence.count
                for section in sections {
                    let kinds=section.filter{options.kinds.contains($0)}; if kinds.isEmpty { continue }
                    var offset=0
                    while true {
                        try Task.checkCancellation()
                        let page=try await store.findings(session:session.id,template:session.template,kinds:kinds,limit:120,offset:offset)
                        if page.isEmpty { break }
                        let part=SessionReportFormatter.document(session:session,findings:page,referenceOffset:references)
                        try write("\n"+(format == .markdown ? SessionReportFormatter.markdown(part,includeEvidence:options.evidence,includeHeader:false,includeEvidenceAnnex:false):SessionReportFormatter.plainText(part,includeEvidence:options.evidence,includeHeader:false,includeEvidenceAnnex:false))); try recordEvidence(part)
                        references += part.evidence.count; offset += page.count
                    }
                }
                if let evidenceFile {
                    try evidenceFile.seek(toOffset:0)
                    var firstEvidence=true
                    for try await line in evidenceFile.bytes.lines {
                        try Task.checkCancellation()
                        let page=try JSONDecoder().decode(EvidencePage.self,from:Data(line.utf8))
                        let report=SessionReportFormatter.document(session:session,findings:page.findings,referenceOffset:page.referenceOffset)
                        try write("\n"+SessionReportFormatter.evidenceAnnex(report,markdown:format == .markdown,includeHeading:firstEvidence))
                        firstEvidence=false
                    }
                }
            }
            if options.bookmarks {
                var offset=0; var first=true
                while true {
                    let markers=try await store.bookmarks(session:session.id,offset:offset)
                    if markers.isEmpty { break }
                    if offset==0,format != .json { try write(format == .markdown ? "\n## Marcadores y notas\n\n":"\nMarcadores y notas\n\n") }
                    for marker in markers {
                        if format == .json {
                            if !first { try write(",") }; try handle.write(contentsOf:encoder.encode(marker)); first=false
                        } else { try write(SessionReportFormatter.bookmarkText(marker,markdown:format == .markdown)) }
                    }
                    offset += markers.count
                }
            }
            if format == .json { try write("],\"transcript\":[") }
            else if options.transcript {
                let title=options.originalTranscript ? "Transcripción original sin correcciones":"Transcripción completa"
                try write(format == .markdown ? "\n## \(title)\n\n":"\n\(title)\n\n")
            }
            if options.transcript {
                var cursor:Int64=0; var first=true
                while true {
                    let rows=try await store.segments(session:session.id,after:cursor,limit:200)
                    if rows.isEmpty { break }
                    for (seq,value) in rows {
                        let segment=transcriptVariant(value,original:options.originalTranscript)
                        if format == .json { if !first { try write(",") }; try handle.write(contentsOf:encoder.encode(segment)); first=false }
                        else { try write("[\(timestamp(segment.start)) – \(timestamp(segment.end))] \(segment.source.title)\n\(segment.text)\n\n") }
                        cursor=seq
                    }
                }
            }
            if format == .json {
                try write("]")
                if options.discourse {
                    try write(",\"discourse\":{\"state\":")
                    try handle.write(contentsOf:encoder.encode(discourseState))
                    try write(",\"items\":[")
                    var offset=0; var first=true
                    while true {
                        let page=try await store.discourseFindings(session:session.id,limit:100,offset:offset)
                        for finding in page {
                            if !first { try write(",") }; first=false
                            try handle.write(contentsOf:encoder.encode(finding))
                        }
                        offset += page.count
                        if page.count<100 { break }
                    }
                    try write("],\"participation\":")
                    try handle.write(contentsOf:encoder.encode(try await store.participation(session:session.id)))
                    try write("}")
                }
                try write("}")
            } else if options.discourse {
                try write(format == .markdown ? "\n## Análisis de discurso\n\n":"\nAnálisis de discurso\n\n")
                var offset=0
                while true {
                    let page=try await store.discourseFindings(session:session.id,limit:100,offset:offset)
                    for finding in page {
                        let heading=finding.kind.title+" · "+timestamp(finding.start)
                        try write((format == .markdown ? "**"+heading+"**":heading)+"\n"+finding.text+"\n")
                        if options.evidence { for citation in finding.evidence { try write("["+timestamp(citation.start)+"] «"+citation.quote+"»\n") } }
                        try write("\n")
                    }
                    offset += page.count
                    if page.count<100 { break }
                }
                try write(format == .markdown ? "\n## Participación\n\n":"\nParticipación\n\n")
                for speaker in try await store.participation(session:session.id) {
                    try write((speaker.name ?? "Hablante "+String(speaker.number))+" · "+speaker.source.title+" · "+timestamp(speaker.seconds)+" · "+String(speaker.turns)+" turnos\n")
                }
            }
            try handle.synchronize()
        }
        guard revision == (try await store.transcriptRevision(session:session.id)) else {
            throw LAIError.message("La transcripción cambió durante la exportación. Intenta de nuevo.")
        }
        if options.discourse, (try await store.discourseState(session:session.id))?.updated != discourseState?.updated {
            throw LAIError.message("El análisis de discurso cambió durante la exportación. Reintenta.")
        }
        if FileManager.default.fileExists(atPath:url.path) { _=try FileManager.default.replaceItemAt(url,withItemAt:temp) }
        else { try FileManager.default.moveItem(at:temp,to:url) }
    }
}
