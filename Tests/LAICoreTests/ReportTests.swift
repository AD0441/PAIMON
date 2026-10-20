import Foundation
import Testing
import AppKit
import PDFKit
@testable import LAICore

private func reportFixture() -> (Session,[Finding]) {
    var session=Session(title:"Coordinación del laboratorio",settings:AppSettings())
    session.duration=1920
    let quote="Revisamos el presupuesto del laboratorio. Acordamos comprar dos micrófonos. Ana enviará la cotización el viernes. Falta decidir dónde instalar los equipos."
    let values:[(FindingKind,String)]=[
        (.topic,"Presupuesto del laboratorio"),
        (.overview,"Se revisó el presupuesto del laboratorio y la necesidad de adquirir micrófonos. La ubicación de los equipos continúa pendiente."),
        (.idea,"Equipamiento: se necesitan dos micrófonos para el laboratorio."),
        (.decision,"Comprar dos micrófonos."),
        (.task,"Enviar la cotización de los micrófonos."),
        (.task,"Decidir dónde instalar los equipos."),
        (.question,"¿Dónde se instalarán los equipos?"),
        (.conclusion,"La compra quedó acordada y la instalación requiere una decisión posterior.")]
    let findings=values.enumerated().map { index,value -> Finding in
        Finding(kind:value.0,text:value.1,segmentID:"system-0",quote:quote,start:0,end:25,owner:index==4 ? "Ana":nil,due:index==4 ? "viernes":nil)
    }
    return (session,findings)
}
@Test func reportStructureSeparatesTasksAndOmitsEmptySections() {
    let (session,findings)=reportFixture()
    let report=SessionReportFormatter.document(session:session,findings:findings)
    #expect(report.sections.map(\.kind)==[.overview,.points,.decisions,.tasks,.questions,.conclusions])
    #expect(report.evidence.map(\.reference)==Array(1...7))
    let tasks=report.sections.first{$0.kind == .tasks}!.items
    #expect(tasks[0].owner=="Ana"); #expect(tasks[0].due=="viernes")
    #expect(tasks[1].owner=="No especificado"); #expect(tasks[1].due=="No especificado")
    #expect(report.metadata.contains("00:32:00"))
    let lecture=SessionReportFormatter.document(session:session,findings:findings.filter{[.overview,.idea].contains($0.kind)})
    #expect(lecture.sections.map(\.kind)==[.overview,.points])
}
@Test @MainActor func richReportPreservesBoldAndRealTableThroughRTF() throws {
    let (session,findings)=reportFixture()
    let report=SessionReportFormatter.document(session:session,findings:findings)
    let rich=SessionReportFormatter.richText(report)
    let data=try rich.data(from:NSRange(location:0,length:rich.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtf])
    let reopened=try NSAttributedString(data:data,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil)
    let text=reopened.string as NSString
    for label in [report.title,"Resumen general","Puntos clave","Compromisos","Equipamiento:"] {
        let range=text.range(of:label); #expect(range.location != NSNotFound)
        let font=try #require(reopened.attribute(.font,at:range.location,effectiveRange:nil) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
    }
    let taskRange=text.range(of:"Enviar la cotización")
    let style=try #require(reopened.attribute(.paragraphStyle,at:taskRange.location,effectiveRange:nil) as? NSParagraphStyle)
    #expect(style.textBlocks.first is NSTextTableBlock)
    let html=SessionReportFormatter.html(report)
    #expect(html.contains("<table>")); #expect(html.contains("<strong>Equipamiento:</strong>"))
    #expect(!html.contains("Evidencias"))
}
@Test func markdownEscapesSourceMarkupAndUsesEvidenceLinks() {
    let (session,findings)=reportFixture()
    let report=SessionReportFormatter.document(session:session,findings:findings)
    let markdown=SessionReportFormatter.markdown(report,includeEvidence:true)
    #expect(markdown.contains("**Equipamiento:**"))
    #expect(markdown.contains("| Tarea | Responsable | Fecha |"))
    #expect(markdown.contains("[↗](#evidencia-1)"))
    #expect(markdown.contains("id=\"evidencia-1\""))
    let clean=SessionReportFormatter.markdown(report)
    #expect(!clean.contains("## Evidencias")); #expect(!clean.contains("(#evidencia-"))
    var marked=findings[2]; marked.text="Etiqueta: <img src=x> | **texto**"
    let safe=SessionReportFormatter.document(session:session,findings:[marked])
    #expect(!SessionReportFormatter.html(safe).contains("<img"))
    #expect(SessionReportFormatter.markdown(safe).contains("\\|"))
}
@Test func pdfKeepsBoldTableAndLinksToOptionalEvidenceAnnex() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let (session,findings)=reportFixture(); try await store.save(session)
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:0,isFinal:true,findings:findings))
    let exporter=SessionExporter(store:store)
    var options=ExportOptions(); options.transcript=false
    let url=directory.appendingPathComponent("report.pdf")
    try await exporter.export(session:session,to:url,format:.pdf,options:options)
    let document=try #require(PDFDocument(url:url))
    #expect(document.string?.contains("Responsable")==true)
    #expect(document.string?.contains("No especificado")==true)
    #expect(document.string?.contains("Evidencias")==true)
    #expect(document.string?.contains("##")==false)
    var links:[PDFAnnotation]=[]
    for index in 0..<document.pageCount {
        let page=try #require(document.page(at:index))
        links += page.annotations.filter{$0.type == "Link"}
    }
    #expect(links.count==7)
    for link in links {
        let target=link.destination ?? (link.action as? PDFActionGoTo)?.destination
        #expect(target?.page != nil)
    }
    let page=try #require(document.page(at:0))
    let attributed=try #require(page.attributedString)
    let heading=(attributed.string as NSString).range(of:"Resumen general")
    let font=try #require(attributed.attribute(.font,at:heading.location,effectiveRange:nil) as? NSFont)
    #expect(font.fontName.lowercased().contains("bold"))
    if let path=ProcessInfo.processInfo.environment["LAI_REPORT_PREVIEW_DIR"] {
        let output=URL(fileURLWithPath:path); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try Data(contentsOf:url).write(to:output.appendingPathComponent("report.pdf"))
        for index in 0..<document.pageCount {
            let image=document.page(at:index)!.thumbnail(of:NSSize(width:1190,height:1684),for:.mediaBox)
            let bitmap=NSBitmapImageRep(data:try #require(image.tiffRepresentation))!
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("page-\(index+1).png"))
        }
    }
    options.evidence=false
    try await exporter.export(session:session,to:url,format:.pdf,options:options)
    let clean=try #require(PDFDocument(url:url))
    #expect(clean.string?.contains("Evidencias")==false)
    #expect(clean.page(at:0)?.annotations.isEmpty==true)
}
@Test func evidenceWindowFindsOldSegmentsWithoutLoadingWholeSession() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let (session,_)=reportFixture(); try await store.save(session)
    for i in 0..<640 { try await store.append(.init(sessionID:session.id,source:.system,start:Double(i),end:Double(i+1),text:"Fragmento \(i)")) }
    let rows=try await store.segmentWindow(session:session.id,segmentID:"system-12000")
    #expect(rows.count<=300)
    #expect(rows.contains{$0.1.id=="system-12000"})
    #expect(try await store.segmentWindow(session:UUID(),segmentID:"system-12000").isEmpty)
}
@Test func longTaskRowsContinueAcrossPDFPagesWithoutLosingText() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let (session,_)=reportFixture(); try await store.save(session)
    let long=Finding(kind:.task,text:"INICIO DE TAREA "+String(repeating:"Revisar parámetros de calibración y condiciones ambientales. ",count:90)+"FIN DE TAREA",segmentID:"system-0",quote:"Revisar parámetros de calibración",start:0,end:10)
    try await store.save(SummarySnapshot(sessionID:session.id,throughRow:0,isFinal:true,findings:[long]))
    var options=ExportOptions(); options.transcript=false; options.evidence=false; options.kinds=[.task]
    let url=directory.appendingPathComponent("long.pdf")
    try await SessionExporter(store:store).export(session:session,to:url,format:.pdf,options:options)
    let document=try #require(PDFDocument(url:url))
    #expect(document.pageCount>1)
    #expect(document.string?.contains("INICIO DE TAREA")==true)
    #expect(document.string?.contains("FIN DE TAREA")==true)
    for index in 0..<document.pageCount { #expect(document.page(at:index)?.string?.contains("Responsable")==true) }
}
