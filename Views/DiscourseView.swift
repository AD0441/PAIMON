import LAICore
import SwiftUI

struct DiscourseView: View {
    var model: AppModel
    @State private var section: Section = .topics
    @State private var findings: [DiscourseFinding] = []
    @State private var topics: [DiscourseTopic] = []
    @State private var speakers: [SpeakerParticipation] = []
    @State private var state: DiscourseState?
    @State private var stale = false
    @State private var page = 0
    @State private var topic: String?
    @State private var error: String?
    private enum Section: String, CaseIterable {
        case topics, arguments, evolution, participation, resources, questions
        var title: String {
            switch self {
            case .topics: "Mapa de temas"; case .arguments: "Mapa de argumentos"; case .evolution: "Evolución de posturas"
            case .participation: "Participación"; case .resources: "Recursos discursivos"; case .questions: "Preguntas y respuestas"
            }
        }
        var kinds: [DiscourseKind] {
            switch self {
            case .arguments: [.proposal, .argument, .objection, .answer]
            case .evolution: [.evolution]
            case .resources: [.definition, .analogy, .example, .generalization, .uncertainty, .certainty]
            case .questions: [.question, .answer]
            default: []
            }
        }
    }
    private struct Request: Hashable {
        let session: UUID?
        let revision: UUID
        let correction: UUID
        let context: String
        let tick: Int
        let section: String
        let page: Int
        let topic: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Análisis de discurso", systemImage: "text.bubble").font(.headline)
                Text("Interpretaciones del texto con citas verificables. Durante la sesión son provisionales; el silencio no implica aceptación ni abandono.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if model.discourseWorking {
                        ProgressView().controlSize(.small)
                        Button("Cancelar") { model.cancelDiscourse() }
                    } else {
                        Button("Analizar discurso") { model.analyzeDiscourse() }
                            .disabled(model.selected == nil || model.pressure || model.summaryWorking || [.importing,.preparing,.stopping].contains(model.state) || DiscourseAnalyzer.unavailableReason != nil)
                    }
                    Spacer()
                }
                if !model.discourseStatus.isEmpty { Text(model.ui(model.discourseStatus)).font(.caption).foregroundStyle(.secondary) }
                if let reason = DiscourseAnalyzer.unavailableReason { Text(model.ui(reason)).font(.caption).foregroundStyle(.secondary) }
                if stale { Text("El texto o el contexto cambió. Actualiza el análisis antes de exportarlo.").font(.caption).foregroundStyle(.secondary) }
                if let state {
                    Text(model.ui(state.final ? "Análisis final del texto disponible" : "Análisis provisional") + " · " + state.updated.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if state.rejected > 0 {
                        Text("Se omitieron interpretaciones sin respaldo suficiente.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(model.ui(error)).font(.caption).foregroundStyle(.secondary) }
                Picker("Explorar", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text(model.ui($0.title)).tag($0) }
                }.onChange(of: section) { page = 0 }
                if let topic {
                    HStack {
                        Text(topic).font(.caption)
                        Button("Quitar filtro") { self.topic = nil; page = 0 }
                    }
                }
                Divider()
                if section == .participation { participation }
                else if section == .topics {
                    if topics.isEmpty { Text("Analiza la transcripción para explorar sus temas.").foregroundStyle(.secondary) }
                    ForEach(topics) { value in
                        Button {
                            section = .arguments
                            topic = value.id
                            page = 0
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(value.title).fontWeight(.semibold)
                                if !value.parent.isEmpty { Text(value.parent).font(.caption).foregroundStyle(.secondary) }
                                Text("\(timestamp(value.first)) – \(timestamp(value.last)) · \(value.mentions) referencias")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    HStack {
                        Button("Anteriores") { page -= 1 }.disabled(page == 0)
                        Spacer()
                        Button("Siguientes") { page += 1 }.disabled(topics.count < 80)
                    }.font(.caption)
                } else {
                    if findings.isEmpty { Text("No hay elementos con citas en esta página.").foregroundStyle(.secondary) }
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(findings) { finding in
                            DiscourseRow(model: model, finding: finding, nested: false)
                        }
                    }
                    HStack {
                        Button("Anteriores") { page -= 1 }.disabled(page == 0)
                        Spacer()
                        Button("Siguientes") { page += 1 }.disabled(findings.count < 80)
                    }.font(.caption)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: Request(session: model.selected, revision: model.discourseRevision, correction: model.sentimentRevision, context: model.sessionContext.engineIdentifier(backend: "discourse"),
                          tick: model.active ? Int(model.elapsed / 5) : 0, section: section.rawValue, page: page, topic: topic)) {
            await reload()
        }
    }

    private var participation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tiempo atribuido por diarización. Los porcentajes se calculan dentro de cada fuente; los intervalos contiguos se agrupan en turnos.")
                .font(.caption).foregroundStyle(.secondary)
            if speakers.isEmpty {
                Text("No hay hablantes atribuidos. Activa Separar voces antes de capturar o importar.")
                    .foregroundStyle(.secondary)
            }
            ForEach(speakers) { speaker in
                let total = speakers.filter { $0.source == speaker.source }.reduce(0) { $0 + $1.seconds }
                VStack(alignment: .leading, spacing: 5) {
                    Text(speaker.name ?? model.ui("Hablante") + " \(speaker.number)").fontWeight(.semibold)
                    Text(model.ui(speaker.source.title)).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: speaker.seconds, total: max(1, total))
                    Text("\(timestamp(speaker.seconds)) · \(speaker.turns) turnos")
                    Text(model.ui("Promedio por turno") + ": " + timestamp(speaker.meanTurn))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reload() async {
        guard let session = model.selectedSession, let store = model.store else { return }
        do {
            let saved = try await store.session(id: session.id) ?? session
            let cached = try await store.discourseState(session: session.id)
            let revision = try await store.transcriptRevision(session: session.id)
            let items = try await store.discourseFindings(session: session.id, kinds: section.kinds, limit: 80, offset: page * 80, topic: topic)
            let map = try await store.discourseTopics(session: session.id, limit: 80, offset: page * 80)
            let participation = try await store.participation(session: session.id)
            try Task.checkCancellation()
            guard model.selected == session.id else { return }
            state = cached; findings = items; topics = map; speakers = participation
            stale = cached.map { $0.stamp != DiscourseAnalyzer.stamp(session: saved, revision: revision) } ?? false
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}

private struct DiscourseRow: View {
    var model: AppModel
    let finding: DiscourseFinding
    let nested: Bool
    @State private var expanded = false
    @State private var related: [DiscourseFinding] = []
    @State private var target: DiscourseFinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(model.ui(finding.kind.title)).font(.caption.weight(.semibold))
                Spacer()
                Text(timestamp(finding.start)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(finding.text).textSelection(.enabled)
            if let target {
                Text(model.ui(finding.relation.title) + " · " + target.text).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(finding.evidence.enumerated()), id: \.offset) { _, citation in
                DisclosureGroup(timestamp(citation.start)) {
                    Text("«\(citation.quote)»").font(.caption).textSelection(.enabled)
                    Button("Ver transcripción") { Task { await model.revealTranscriptSegment(citation.segmentID) } }
                        .font(.caption)
                    if model.selectedSession?.importedFileName != nil {
                        Button("Escuchar fragmento") { Task { await model.playOriginalAudio(start: citation.start, end: citation.end) } }
                            .font(.caption).disabled(model.active)
                    }
                }.font(.caption)
            }
            if !nested, finding.kind == .proposal || finding.kind == .question {
                DisclosureGroup("Relaciones y evolución", isExpanded: $expanded) {
                    if expanded {
                        if related.isEmpty { Text("Sin respuesta o vínculo explícito encontrado en este análisis.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(related) { DiscourseRow(model: model, finding: $0, nested: true) }
                    }
                }.font(.caption)
                .task(id: expanded) {
                    guard expanded, let session = model.selected else { return }
                    related = (try? await model.store?.discourseRelated(session: session, target: finding.id)) ?? []
                }
            }
            Divider()
        }
        .task(id: finding.target) {
            guard let id = finding.target, let session = model.selected else { return }
            target = try? await model.store?.discourseFinding(session: session, id: id)
        }
    }
}
