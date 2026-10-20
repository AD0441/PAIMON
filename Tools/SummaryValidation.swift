import Foundation
import LAICore

func validateSummaryQuality(output:URL) async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("paimon-summary-validation-\(UUID())")
    defer { try? FileManager.default.removeItem(at:directory) }
    let store=try SessionStore(directory:directory)
    let session=Session(title:"Muestra sintética de resumen",settings:AppSettings()); try await store.save(session)
    let paragraphs=[
        "La biblioteca propone incorporar un catálogo digital. Permitirá consultar la ubicación y disponibilidad de los libros desde los computadores del campus. La propuesta se debe evaluar antes de aprobarla.",
        "El catálogo digital reuniría las colecciones de las distintas sedes. La biblioteca quiere reducir el tiempo de búsqueda de los libros y facilitar la consulta de materiales de estudio.",
        "La formación del personal de biblioteca se realizará mediante talleres. Los talleres explicarán cómo consultar el catálogo y actualizar los registros de libros. Todavía no se ha definido un calendario para esta formación.",
        "El laboratorio necesita renovar los microscopios. Se propone revisar primero su estado y comparar las alternativas de reparación y compra. La propuesta todavía no tiene presupuesto aprobado.",
        "Los microscopios son necesarios para las prácticas de biología. El laboratorio busca mejorar la observación de las muestras. Se debe comprobar cuáles de los equipos actuales pueden continuar utilizándose.",
        "El plan del laboratorio considera mantenimiento de microscopios y disponibilidad de materiales para las clases. Se plantea coordinar estas actividades para evitar interrupciones de las prácticas de biología.",
        "Para organizar las salas se propone crear un calendario de reservas. El calendario mostraría horarios disponibles y permitiría consultar las reservas antes de programar talleres y reuniones.",
        "La propuesta del calendario de salas busca evitar reservas duplicadas. Las unidades académicas necesitan conocer los horarios de uso y los cambios de programación. Aún falta elegir la herramienta que se utilizará.",
        "La biblioteca, el laboratorio y la coordinación de salas presentaron propuestas distintas. El catálogo, los microscopios y el calendario de reservas requieren evaluación antes de su puesta en marcha.",
        "Las propuestas se revisarán considerando recursos disponibles y continuidad de las clases. No se asignaron responsables individuales ni fechas. No hubo aprobación explícita de presupuestos en este material.",
        "Se reiteró que el catálogo facilitaría la consulta de libros, los microscopios apoyarían las prácticas y el calendario mejoraría la organización de salas. Cada propuesta responde a una necesidad distinta del campus.",
        "Bien, en el área de coordinación."
    ]
    for (i,text) in paragraphs.enumerated() { try await store.append(.init(sessionID:session.id,source:.file,start:Double(i*30),end:Double(i*30+25),text:text)) }
    let start=ProcessInfo.processInfo.systemUptime
    guard let summary=try await SummaryCoordinator(store:store).update(session:session,engine:FoundationSummaryEngine(),final:true) else { throw SummaryResponseError.insufficient }
    let text=summary.findings.map(\.text).joined(separator:" ").folding(options:[.caseInsensitive,.diacriticInsensitive],locale:nil)
    let covered=["catalogo","microscop","calendario"].allSatisfy{text.contains($0)}
    let grounded=summary.findings.allSatisfy { finding in finding.evidence.allSatisfy { reference in paragraphs.contains(reference.quote) && reference.segmentID != "file-330000" } }
    let passed=summary.isFinal && summary.findings.contains{$0.kind == .overview} && covered && grounded
    let result:[String:Any]=["passed":passed,"synthetic":true,"segments":paragraphs.count,"findings":summary.findings.count,"overviewPresent":summary.findings.contains{$0.kind == .overview},"allThreeTopicsCovered":covered,"originalQuotesOnly":grounded,"processingVersion":summary.processingVersion ?? 0,"elapsedSeconds":ProcessInfo.processInfo.systemUptime-start,"clientFootprintMB":ResourceMetrics.current().footprintMB]
    try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:output)
    try await SessionExporter(store:store).export(session:session,to:output.deletingPathExtension().appendingPathExtension("md"),format:.markdown,options:ExportOptions())
    guard passed else { throw LAIError.message("La muestra no cubre los tres temas o carece de evidencia") }
    print("PASS: tres temas, resumen general, citas originales y exclusión del fragmento introductorio. \(summary.findings.count) hallazgos.")
}
