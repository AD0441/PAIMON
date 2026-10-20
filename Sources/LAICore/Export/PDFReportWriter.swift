import Foundation
import CoreGraphics
import CoreText
import AppKit

/// Scoped to the export actor. Writes pages incrementally, including long table rows.
final class PDFReportWriter {
    private let context:CGContext
    private let width:CGFloat=507
    private let margin:CGFloat=44
    private var y:CGFloat=798
    private var page=0
    private var closed=false
    private static let referenceKey=NSAttributedString.Key("LAIReference")
    init(url:URL) throws {
        var box=CGRect(x:0,y:0,width:595,height:842)
        guard let consumer=CGDataConsumer(url:url as CFURL),
              let context=CGContext(consumer:consumer,mediaBox:&box,nil) else { throw LAIError.message("No se pudo crear el PDF") }
        self.context=context
        newPage()
    }
    deinit { close() }
    func close() {
        guard !closed else { return }
        context.endPDFPage(); context.closePDF(); closed=true
    }
    private func newPage() {
        if page>0 { context.endPDFPage() }
        page += 1; context.beginPDFPage(nil); context.textMatrix = .identity; y=798
        let footer=styled("\(page)",size:9,color:0.45)
        draw(footer,range:CFRange(location:0,length:0),rect:CGRect(x:520,y:23,width:31,height:15))
    }
    private func ensure(_ height:CGFloat) { if y-height<48 { newPage() } }
    private func styled(_ text:String,size:CGFloat=11,bold:Bool=false,color:CGFloat=0.12,emphasis:Bool=false,reference:Int?=nil) -> NSAttributedString {
        let font=CTFontCreateWithName((bold ? "Helvetica-Bold":"Helvetica") as CFString,size,nil)
        let paragraph=NSMutableParagraphStyle(); paragraph.lineSpacing=3
        let attributes:[NSAttributedString.Key:Any]=[.init(kCTFontAttributeName as String):font,.init(kCTForegroundColorAttributeName as String):CGColor(gray:color,alpha:1),.paragraphStyle:paragraph]
        let value=NSMutableAttributedString(string:text,attributes:attributes)
        if emphasis { value.addAttribute(.init(kCTFontAttributeName as String),value:CTFontCreateWithName("Helvetica-Bold" as CFString,size,nil),range:NSRange(location:0,length:(SessionReportFormatter.emphasizedPrefix(in:text) as NSString).length)) }
        if let reference {
            let marker=NSMutableAttributedString(string:"  ↗",attributes:attributes)
            marker.addAttribute(Self.referenceKey,value:reference,range:NSRange(location:0,length:marker.length))
            marker.addAttribute(.init(kCTForegroundColorAttributeName as String),value:CGColor(gray:0.35,alpha:1),range:NSRange(location:0,length:marker.length))
            value.append(marker)
        }
        return value
    }
    private func height(_ value:NSAttributedString,width:CGFloat,offset:Int=0) -> CGFloat {
        guard offset<value.length else { return 0 }
        let setter=CTFramesetterCreateWithAttributedString(value)
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location:offset,length:0),nil,CGSize(width:width,height:100_000),nil).height)+3
    }
    @discardableResult private func draw(_ value:NSAttributedString,range:CFRange,rect:CGRect) -> Int {
        let setter=CTFramesetterCreateWithAttributedString(value)
        let frame=CTFramesetterCreateFrame(setter,range,CGPath(rect:rect,transform:nil),nil)
        CTFrameDraw(frame,context)
        let lines=CTFrameGetLines(frame) as! [CTLine]
        var origins=[CGPoint](repeating:.zero,count:lines.count)
        CTFrameGetLineOrigins(frame,CFRange(location:0,length:0),&origins)
        for (index,line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attrs=CTRunGetAttributes(run) as NSDictionary
                guard let reference=attrs[Self.referenceKey.rawValue] as? Int else { continue }
                let runRange=CTRunGetStringRange(run)
                guard !value.attributedSubstring(from:NSRange(location:runRange.location,length:runRange.length)).string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { continue }
                var ascent:CGFloat=0; var descent:CGFloat=0
                let runWidth=CTRunGetTypographicBounds(run,CFRange(location:0,length:0),&ascent,&descent,nil)
                let offset=CTLineGetOffsetForStringIndex(line,CTRunGetStringRange(run).location,nil)
                let link=CGRect(x:rect.minX+origins[index].x+offset,y:rect.minY+origins[index].y-descent,width:runWidth,height:ascent+descent)
                context.setDestination("evidence-\(reference)" as CFString,for:link)
            }
        }
        return CTFrameGetVisibleStringRange(frame).length
    }
    private func paragraph(_ value:NSAttributedString,after:CGFloat=10) throws {
        var offset=0
        while offset<value.length {
            ensure(35)
            let available=y-48
            let required=height(value,width:width,offset:offset)
            let h=min(required,available)
            let drawn=draw(value,range:CFRange(location:offset,length:0),rect:CGRect(x:margin,y:y-h,width:width,height:h))
            guard drawn>0 else { throw LAIError.message("No se pudo distribuir el texto en el PDF") }
            offset += drawn; y -= h
            if offset<value.length { newPage() }
        }
        y -= after
    }
    func heading(_ text:String) throws {
        ensure(72); y -= 7
        try paragraph(styled(text,size:14,bold:true),after:10)
    }
    func report(_ report:SessionReport,includeEvidence:Bool,includeHeader:Bool=true,includeEvidenceAnnex:Bool=true) throws {
        if includeHeader {
            try paragraph(styled(report.title,size:23,bold:true),after:7)
            try paragraph(styled(report.metadata,size:10,color:0.4),after:18)
        }
        if report.sections.isEmpty { try paragraph(styled("El resumen todavía no está disponible.")) }
        for section in report.sections {
            try heading(section.kind.title)
            if section.kind == .tasks { try tasks(section.items,includeEvidence:includeEvidence) }
            else {
                for item in section.items {
                    let bullet=section.kind == .overview ? "":"• "
                    let value=NSMutableAttributedString(attributedString:styled(item.finding.text,emphasis:section.kind != .overview,reference:includeEvidence ? item.reference:nil))
                    if !bullet.isEmpty { value.insert(styled(bullet),at:0) }
                    try paragraph(value)
                }
            }
        }
        if includeEvidence,includeEvidenceAnnex { try evidence(report,first:true) }
    }
    func evidence(_ report:SessionReport,first:Bool) throws {
        if !report.evidence.isEmpty {
            if first { newPage(); try heading("Evidencias") }
            for item in report.evidence {
                ensure(75)
                context.addDestination("evidence-\(item.reference)" as CFString,at:CGPoint(x:margin,y:y))
                for source in item.sources {
                    try paragraph(styled("[\(item.reference)] \(source.sourceTitle) · \(timestamp(source.start)) - \(timestamp(source.end))",size:10,bold:true),after:5)
                    try paragraph(styled("«\(source.quote)»",size:10,color:0.3),after:15)
                }
            }
        }
    }
    private func tasks(_ items:[ReportItem],includeEvidence:Bool) throws {
        let widths=[width*0.55,width*0.225,width*0.225]
        func header() {
            var x=margin
            for (i,title) in ["Tarea","Responsable","Fecha"].enumerated() {
                let rect=CGRect(x:x,y:y-31,width:widths[i],height:31)
                context.setFillColor(CGColor(gray:0.95,alpha:1)); context.fill(rect)
                context.setStrokeColor(CGColor(gray:0.8,alpha:1)); context.setLineWidth(0.5); context.stroke(rect)
                draw(styled(title,size:10,bold:true),range:CFRange(location:0,length:0),rect:rect.insetBy(dx:7,dy:6))
                x += widths[i]
            }
            y -= 31
        }
        ensure(80); header()
        for item in items {
            let cells=[styled(item.finding.text,size:10,reference:includeEvidence ? item.reference:nil),styled(item.owner,size:10),styled(item.due,size:10)]
            var offsets=[0,0,0]
            while zip(offsets,cells).contains(where:{$0.0<$0.1.length}) {
                if y<105 { newPage(); header() }
                let remaining=cells.enumerated().map { height($0.element,width:widths[$0.offset]-14,offset:offsets[$0.offset]) }.max() ?? 0
                let rowHeight=min(max(32,remaining+14),y-48)
                var x=margin; var progressed=false
                for column in 0..<3 {
                    let rect=CGRect(x:x,y:y-rowHeight,width:widths[column],height:rowHeight)
                    context.setStrokeColor(CGColor(gray:0.82,alpha:1)); context.setLineWidth(0.5); context.stroke(rect)
                    if offsets[column]<cells[column].length {
                        let count=draw(cells[column],range:CFRange(location:offsets[column],length:0),rect:rect.insetBy(dx:7,dy:7))
                        offsets[column] += count; progressed = progressed || count>0
                    }
                    x += widths[column]
                }
                guard progressed else { throw LAIError.message("No se pudo distribuir una fila del PDF") }
                y -= rowHeight
                if zip(offsets,cells).contains(where:{$0.0<$0.1.length}) { newPage(); header() }
            }
        }
        y -= 12
    }
    func transcript(_ segments:[TranscriptSegment]) throws {
        for segment in segments {
            ensure(65)
            try paragraph(styled("\(timestamp(segment.start)) - \(timestamp(segment.end)) · \(segment.source.title)",size:9,bold:true,color:0.4),after:4)
            try paragraph(styled(segment.text,size:10),after:12)
        }
    }
    func startTranscript() throws { newPage(); try heading("Transcripción completa") }
    func bookmarks(_ bookmarks:[SessionBookmark],start:Bool) throws {
        if start { newPage(); try heading("Marcadores y notas") }
        for bookmark in bookmarks {
            ensure(60)
            try paragraph(styled(timestamp(bookmark.time),size:10,bold:true),after:4)
            try paragraph(styled(bookmark.note.isEmpty ? "Marcador":bookmark.note),after:12)
        }
    }
}
