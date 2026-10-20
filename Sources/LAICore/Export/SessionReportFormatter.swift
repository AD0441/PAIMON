import Foundation
import AppKit

public enum ReportSectionKind:String,Sendable,CaseIterable {
    case overview, points, decisions, tasks, questions, conclusions
    public var title:String {
        switch self {
        case .overview: "Resumen general"
        case .points: "Puntos clave"
        case .decisions: "Acuerdos y decisiones"
        case .tasks: "Compromisos"
        case .questions: "Preguntas abiertas"
        case .conclusions: "Conclusiones"
        }
    }
}
public struct ReportItem:Identifiable,Sendable {
    public var finding:Finding
    public var reference:Int
    public var id:UUID { finding.id }
    public var sources:[FindingEvidence] { finding.evidence }
    public var evidenceText:String { sources.map{"\($0.sourceTitle) · \(timestamp($0.start)) - \(timestamp($0.end))\n«\($0.quote)»"}.joined(separator:"\n\n") }
    public var sourceTitle:String {
        AudioSource.allCases.first { finding.segmentID.hasPrefix($0.rawValue+"-") }?.title ?? "Fuente local"
    }
    public var owner:String { finding.owner.flatMap { $0.isEmpty ? nil:$0 } ?? "No especificado" }
    public var due:String { finding.due.flatMap { $0.isEmpty ? nil:$0 } ?? "No especificado" }
}
public struct ReportSection:Identifiable,Sendable {
    public var kind:ReportSectionKind
    public var items:[ReportItem]
    public var id:ReportSectionKind { kind }
}
public struct SessionReport:Sendable {
    public var title:String
    public var metadata:String
    public var sections:[ReportSection]
    public var evidence:[ReportItem] { sections.flatMap(\.items) }
}

/// One semantic report drives the screen, clipboard and exports. Styling adds no claims.
public enum SessionReportFormatter {
    public static func bookmarkText(_ bookmark:SessionBookmark,markdown:Bool) -> String {
        let note=bookmark.note.isEmpty ? "Marcador":bookmark.note
        return markdown ? "- **\(timestamp(bookmark.time))** \(md(note))\n\n":"[\(timestamp(bookmark.time))] \(note)\n\n"
    }
    public static func document(session:Session,findings:[Finding],referenceOffset:Int=0) -> SessionReport {
        let generic=["Nueva sesión","","Sesión"]
        let title=generic.contains(session.title) ? (findings.first{$0.kind == .topic}?.text ?? "Resumen de la sesión"):session.title
        let date=session.created.formatted(.dateTime.locale(Locale(identifier:"es_CL")).day().month(.wide).year().hour().minute())
        var reference=referenceOffset
        var sections:[ReportSection]=[]
        for kind in ReportSectionKind.allCases {
            let types:[FindingKind]
            switch kind {
            case .overview: types=[.overview]
            case .points: types=[.idea,.concept]
            case .decisions: types=[.decision]
            case .tasks: types=[.task]
            case .questions: types=[.question]
            case .conclusions: types=[.conclusion]
            }
            var seen=Set<String>()
            let values=findings.filter { types.contains($0.kind) && seen.insert($0.text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:nil)).inserted }
            guard !values.isEmpty else { continue }
            sections.append(ReportSection(kind:kind,items:values.map { finding in
                reference += 1; return ReportItem(finding:finding,reference:reference)
            }))
        }
        return SessionReport(title:title,metadata:"\(date) · \(timestamp(session.duration)) · \(session.template.title)",sections:sections)
    }
    /// Emphasize an existing phrase without inventing a heading.
    public static func emphasizedPrefix(in text:String) -> String {
        if let colon=text.firstIndex(of:":"),text.distance(from:text.startIndex,to:colon)<=65 { return String(text[...colon]) }
        let words=text.split(whereSeparator:{$0.isWhitespace}).prefix(6)
        guard let last=words.last else { return "" }
        return String(text[..<last.endIndex])
    }
    public static func text(session:Session,findings:[Finding]) -> String {
        plainText(document(session:session,findings:findings))
    }
    public static func plainText(_ report:SessionReport,includeEvidence:Bool=false,includeHeader:Bool=true,includeEvidenceAnnex:Bool=true) -> String {
        var blocks=includeHeader ? [report.title,report.metadata]:[]
        if report.sections.isEmpty { blocks.append("El resumen todavía no está disponible.") }
        for section in report.sections {
            var lines=[section.kind.title]
            if section.kind == .tasks { lines.append("Tarea | Responsable | Fecha") }
            for item in section.items {
                let ref=includeEvidence ? " [\(item.reference)]":""
                if section.kind == .tasks { lines.append("\(item.finding.text) | \(item.owner) | \(item.due)\(ref)") }
                else { lines.append((section.kind == .overview ? "":"• ")+item.finding.text+ref) }
            }
            blocks.append(lines.joined(separator:section.kind == .overview ? "\n\n":"\n"))
        }
        if includeEvidence,includeEvidenceAnnex,!report.evidence.isEmpty {
            blocks.append(evidenceAnnex(report,markdown:false))
        }
        return blocks.joined(separator:"\n\n")+"\n"
    }
    public static func markdown(_ report:SessionReport,includeEvidence:Bool=false,includeHeader:Bool=true,includeEvidenceAnnex:Bool=true) -> String {
        var blocks=includeHeader ? ["# "+md(report.title),md(report.metadata)]:[]
        if report.sections.isEmpty { blocks.append("El resumen todavía no está disponible.") }
        for section in report.sections {
            var lines=["## "+section.kind.title]
            if section.kind == .tasks { lines += ["| Tarea | Responsable | Fecha |","| --- | --- | --- |"] }
            for item in section.items {
                let ref=includeEvidence ? " [↗](#evidencia-\(item.reference))":""
                if section.kind == .tasks { lines.append("| \(md(item.finding.text))\(ref) | \(md(item.owner)) | \(md(item.due)) |") }
                else if section.kind == .overview { lines.append(md(item.finding.text)+ref) }
                else { lines.append("- "+markdownPoint(item.finding.text)+ref) }
            }
            blocks.append(lines.joined(separator:section.kind == .tasks ? "\n":"\n\n"))
        }
        if includeEvidence,includeEvidenceAnnex,!report.evidence.isEmpty {
            blocks.append(evidenceAnnex(report,markdown:true))
        }
        return blocks.joined(separator:"\n\n")+"\n"
    }
    public static func evidenceAnnex(_ report:SessionReport,markdown:Bool,includeHeading:Bool=true) -> String {
        guard !report.evidence.isEmpty else { return "" }
        if !markdown { return (includeHeading ? "Evidencias\n\n":"")+report.evidence.map{"[\($0.reference)] \($0.evidenceText)"}.joined(separator:"\n\n")+"\n\n" }
        return (includeHeading ? "## Evidencias\n\n":"")+report.evidence.map { item in
            "<a id=\"evidencia-\(item.reference)\"></a>\n\n"+item.sources.enumerated().map { index,source in
                "**[\(item.reference)\(item.sources.count>1 ? ".\(index+1)":"")] \(source.sourceTitle) · \(timestamp(source.start)) - \(timestamp(source.end))**\n\n> \(md(source.quote))"
            }.joined(separator:"\n\n")
        }.joined(separator:"\n\n")+"\n\n"
    }
    public static func html(_ report:SessionReport) -> String {
        var body="<h1>\(escapeHTML(report.title))</h1><p class=\"metadata\">\(escapeHTML(report.metadata))</p>"
        for section in report.sections {
            body += "<h2>\(section.kind.title)</h2>"
            if section.kind == .tasks {
                body += "<table><thead><tr><th>Tarea</th><th>Responsable</th><th>Fecha</th></tr></thead><tbody>"
                for item in section.items { body += "<tr><td>\(escapeHTML(item.finding.text))</td><td>\(escapeHTML(item.owner))</td><td>\(escapeHTML(item.due))</td></tr>" }
                body += "</tbody></table>"
            } else if section.kind == .overview {
                for item in section.items { body += "<p>\(escapeHTML(item.finding.text))</p>" }
            } else { body += "<ul>"+section.items.map { "<li>\(htmlPoint($0.finding.text))</li>" }.joined()+"</ul>" }
        }
        return "<!doctype html><html><head><meta charset=\"utf-8\"><style>body{font:12pt -apple-system,Helvetica,Arial;color:#20252b;line-height:1.5}h1{font-size:22pt}h2{font-size:14pt;margin-top:20pt}.metadata{color:#60656b;font-size:10pt}table{border-collapse:collapse;width:100%}th,td{border:1px solid #d7dce0;padding:8pt;text-align:left;vertical-align:top}th{font-weight:bold;background:#f2f4f5}</style></head><body>\(body)</body></html>"
    }
    public static func richText(_ report:SessionReport) -> NSAttributedString {
        let result=NSMutableAttributedString(string:"")
        func append(_ text:String,size:CGFloat=12,bold:Bool=false,space:CGFloat=8) {
            let paragraph=NSMutableParagraphStyle(); paragraph.lineSpacing=3; paragraph.paragraphSpacing=space
            result.append(NSAttributedString(string:text+"\n",attributes:[.font:bold ? NSFont.boldSystemFont(ofSize:size):NSFont.systemFont(ofSize:size),.foregroundColor:NSColor.black,.paragraphStyle:paragraph]))
        }
        append(report.title,size:22,bold:true,space:6)
        append(report.metadata,size:10,space:16)
        for section in report.sections {
            append(section.kind.title,size:14,bold:true,space:9)
            if section.kind == .tasks {
                let table=NSTextTable(); table.numberOfColumns=3; table.collapsesBorders=true
                let rows=[["Tarea","Responsable","Fecha"]]+section.items.map{[$0.finding.text,$0.owner,$0.due]}
                for (row,cells) in rows.enumerated() {
                    for (column,cell) in cells.enumerated() {
                        let block=NSTextTableBlock(table:table,startingRow:row,rowSpan:1,startingColumn:column,columnSpan:1)
                        block.setValue(column==0 ? 55:22.5,type:.percentageValueType,for:.width)
                        block.setWidth(6,type:.absoluteValueType,for:.padding)
                        block.setWidth(0.5,type:.absoluteValueType,for:.border)
                        block.setBorderColor(NSColor.lightGray)
                        if row==0 { block.backgroundColor=NSColor(white:0.95,alpha:1) }
                        let paragraph=NSMutableParagraphStyle(); paragraph.textBlocks=[block]; paragraph.paragraphSpacing=0
                        result.append(NSAttributedString(string:cell+"\n",attributes:[.font:row==0 ? NSFont.boldSystemFont(ofSize:11):NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.black,.paragraphStyle:paragraph]))
                    }
                }
                append("",size:6,space:6)
            } else {
                for item in section.items {
                    let bullet=section.kind == .overview ? "":"• "
                    result.append(richParagraph(item.finding.text,bullet:bullet,emphasis:section.kind != .overview))
                }
            }
        }
        return result
    }
    private static func richParagraph(_ text:String,bullet:String,emphasis:Bool) -> NSAttributedString {
        let paragraph=NSMutableParagraphStyle(); paragraph.lineSpacing=3; paragraph.paragraphSpacing=8
        paragraph.headIndent=bullet.isEmpty ? 0:14
        let value=NSMutableAttributedString(string:bullet+text+"\n",attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.black,.paragraphStyle:paragraph])
        if emphasis { value.addAttribute(.font,value:NSFont.boldSystemFont(ofSize:12),range:NSRange(location:(bullet as NSString).length,length:(emphasizedPrefix(in:text) as NSString).length)) }
        return value
    }
    private static func md(_ text:String) -> String {
        var value=text.replacingOccurrences(of:"\n",with:" ")
        for character in ["\\","`","*","_","[","]","<",">","|","#"] { value=value.replacingOccurrences(of:character,with:"\\"+character) }
        return value
    }
    private static func markdownPoint(_ text:String) -> String {
        let prefix=emphasizedPrefix(in:text)
        return prefix.isEmpty ? md(text):"**\(md(prefix))**"+md(String(text.dropFirst(prefix.count)))
    }
    private static func htmlPoint(_ text:String) -> String {
        let prefix=emphasizedPrefix(in:text)
        return "<strong>\(escapeHTML(prefix))</strong>"+escapeHTML(String(text.dropFirst(prefix.count)))
    }
    private static func escapeHTML(_ text:String) -> String {
        text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
    }
}
