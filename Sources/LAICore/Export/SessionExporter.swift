import Foundation
public enum ExportFormat: String, CaseIterable, Sendable { case txt, markdown="md", pdf, json }
public struct ExportOptions: Sendable {
    public var transcript=true
    public var evidence=true
    public var bookmarks=true
    public var kinds:Set<FindingKind>=Set(FindingKind.allCases)
    public init() {}
}
public actor SessionExporter {
    private struct EvidencePage:Codable { var findings:[Finding]; var referenceOffset:Int }
    private let store:SessionStore
    public init(store:SessionStore) { self.store=store }
    public func export(session:Session,to url:URL,format:ExportFormat,options:ExportOptions) async throws {
        let temp=url.deletingLastPathComponent().appendingPathComponent(".lai-export-\(UUID().uuidString).\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at:temp) }
        let evidenceURL=FileManager.default.temporaryDirectory.appendingPathComponent("paimon-evidence-\(UUID()).jsonl")
        FileManager.default.createFile(atPath:evidenceURL.path,contents:nil,attributes:[.posixPermissions:0o600])
        let evidenceFile=try FileHandle(forWritingTo:evidenceURL)
        defer { try? evidenceFile.close(); try? FileManager.default.removeItem(at:evidenceURL) }
        func recordEvidence(_ report:SessionReport) throws {
            guard options.evidence,format != .json,let first=report.evidence.first else { return }
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
            var firstEvidence=true
            for try await line in evidenceURL.lines {
                try Task.checkCancellation()
                let page=try JSONDecoder().decode(EvidencePage.self,from:Data(line.utf8))
                try writer.evidence(SessionReportFormatter.document(session:session,findings:page.findings,referenceOffset:page.referenceOffset),first:firstEvidence)
                firstEvidence=false
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
                try writer.startTranscript()
                var cursor:Int64=0
                while true {
                    let rows=try await store.segments(session:session.id,after:cursor,limit:60)
                    if rows.isEmpty { break }
                    try writer.transcript(rows.map(\.1)); cursor=rows.last!.0
                }
            }
            writer.close()
        } else {
            FileManager.default.createFile(atPath:temp.path,contents:nil,attributes:[.posixPermissions:0o600])
            let handle=try FileHandle(forWritingTo:temp); defer { try? handle.close() }
            func write(_ text:String) throws { try handle.write(contentsOf:Data(text.utf8)) }
            if format == .json {
                try write("{\"schemaVersion\":1,\"session\":")
                // Deliberately omit settings containing local executable/model paths.
                let metadata:[String:Any]=["id":session.id.uuidString,"title":session.title,"created":ISO8601DateFormatter().string(from:session.created),"duration":session.duration,"status":session.status,"template":session.template.rawValue]
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
                var firstEvidence=true
                for try await line in evidenceURL.lines {
                    try Task.checkCancellation()
                    let page=try JSONDecoder().decode(EvidencePage.self,from:Data(line.utf8))
                    let report=SessionReportFormatter.document(session:session,findings:page.findings,referenceOffset:page.referenceOffset)
                    try write("\n"+SessionReportFormatter.evidenceAnnex(report,markdown:format == .markdown,includeHeading:firstEvidence)); firstEvidence=false
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
            else if options.transcript { try write(format == .markdown ? "\n## Transcripción completa\n\n":"\nTranscripción completa\n\n") }
            if options.transcript {
                var cursor:Int64=0; var first=true
                while true {
                    let rows=try await store.segments(session:session.id,after:cursor,limit:200)
                    if rows.isEmpty { break }
                    for (seq,segment) in rows {
                        if format == .json { if !first { try write(",") }; try handle.write(contentsOf:encoder.encode(segment)); first=false }
                        else { try write("[\(timestamp(segment.start)) – \(timestamp(segment.end))] \(segment.source.title)\n\(segment.text)\n\n") }
                        cursor=seq
                    }
                }
            }
            if format == .json { try write("]}") }
            try handle.synchronize()
        }
        if FileManager.default.fileExists(atPath:url.path) { _=try FileManager.default.replaceItemAt(url,withItemAt:temp) }
        else { try FileManager.default.moveItem(at:temp,to:url) }
    }
}
