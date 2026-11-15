import Charts
import LAICore
import SwiftUI

struct LiveVocalView: View {
    var model: AppModel
    @State private var points: [LiveVocalResult] = []
    @State private var source: AudioSource = .system
    @State private var selectedID: String?
    @State private var page = 0
    private var displayed: [LiveVocalResult] { points.filter { $0.source == source }.sorted { $0.start < $1.start } }
    private var selected: LiveVocalResult? { displayed.first { $0.id == selectedID } }
    private struct Request: Hashable {
        let session: UUID?
        let revision: UUID
        let tick: Int
        let page: Int
    }

    var body: some View {
        if !points.isEmpty || model.selectedSession?.settings.vocalLiveEnabled == true {
            VStack(alignment: .leading, spacing: 10) {
                Label("Análisis vocal de la captura", systemImage: "waveform.badge.magnifyingglass").font(.headline)
                Text("Ventanas de tres segundos, tomadas de forma espaciada. Son muestras de la sesión, no una evaluación continua de las personas.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.liveVocalStatus.isEmpty { Text(model.ui(model.liveVocalStatus)).font(.caption).foregroundStyle(.secondary) }
                let sources = AudioSource.allCases.filter { candidate in points.contains { $0.source == candidate } }
                if sources.count > 1 {
                    Picker("Fuente de las muestras", selection: $source) {
                        ForEach(sources, id: \.self) { Text(model.ui($0.title)).tag($0) }
                    }
                }
                if displayed.isEmpty { Text("Esperando una ventana de audio disponible…").font(.caption).foregroundStyle(.secondary) }
                else {
                    Chart {
                        ForEach(displayed) { point in
                            PointMark(x: .value("Tiempo", point.start), y: .value("Nivel", point.level)).symbolSize(24)
                        }
                        if let selected { RuleMark(x: .value("Selección", selected.start)).foregroundStyle(Color.secondary) }
                    }
                    .chartXScale(domain: 0...max(1, model.current?.id == model.selected && model.active ? model.elapsed : model.selectedSession?.duration ?? 0, displayed.last?.end ?? 0))
                    .chartYScale(domain: -120.0...0.0)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let seconds = value.as(Double.self) { Text(timestamp(seconds)).monospacedDigit() } }
                    } }
                    .pinChartSelection { time in selectedID = displayed.min { abs($0.start - time) < abs($1.start - time) }?.id }
                    .frame(height: 140)
                    Text("Nivel en dBFS. Haz clic para fijar una muestra.").font(.caption).foregroundStyle(.secondary)
                    if let selected {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(timestamp(selected.start) + " – " + timestamp(selected.end)).fontWeight(.semibold)
                            Text(model.ui("Nivel") + ": " + selected.level.formatted(.number.precision(.fractionLength(1))) + " dBFS")
                            if let pitch = selected.pitch {
                                Text(model.ui("Altura") + ": " + pitch.formatted(.number.precision(.fractionLength(0))) + " Hz")
                            }
                            Text(model.ui("Nivel bajo") + ": " + selected.quietPercent.formatted(.number.precision(.fractionLength(0))) + "%")
                            if let name = selected.model?.title { Text(name).foregroundStyle(.secondary) }
                            if selected.deferred {
                                Text("Inferencia opcional pospuesta para priorizar otras tareas.").foregroundStyle(.secondary)
                            } else if let emotion = selected.emotion {
                                Text(model.ui("Estimación vocal") + ": " + model.ui(emotion.title))
                                if let score = selected.score {
                                    Text(model.ui("Puntuación del modelo") + ": " + score.formatted(.number.precision(.fractionLength(2))))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let distance = selected.distanceFromPrevious {
                                Text(model.ui("Distancia respecto de la muestra anterior") + ": " + distance.formatted(.number.precision(.fractionLength(3))))
                                Text("La distancia compara patrones vocales; no es una probabilidad de emoción.").foregroundStyle(.secondary)
                            }
                            ForEach(selected.sounds) { sound in
                                Text(model.ui(VocalSoundAnalysis.categoryName(sound.identifier)) + " · " + timestamp(sound.start))
                            }
                            Button("Ver transcripción") {
                                Task {
                                    guard let session = model.selected, let store = model.store,
                                          let segment = try? await store.transcriptEvidence(session: session, source: selected.source, start: selected.start, end: selected.end) else { return }
                                    await model.revealTranscriptSegment(segment.id)
                                }
                            }
                        }.font(.caption).textSelection(.enabled)
                    }
                    HStack {
                        if points.count == 120 { Button("Muestras anteriores") { page += 1 } }
                        if page > 0 { Button("Más recientes") { page = 0 } }
                    }.font(.caption)
                }
                Text("Se guardan mediciones y etiquetas. La grabación solo se conserva si activaste Guardar audio.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
            }
            .task(id: Request(session: model.selected, revision: model.liveVocalRevision,
                              tick: model.active ? Int(model.elapsed / 5) : 0, page: page)) { await reload() }
        } else {
            Color.clear.frame(height: 0)
                .task(id: model.selected) { await reload() }
        }
    }

    private func reload() async {
        guard let session = model.selected, let store = model.store else { return }
        guard let values = try? await store.liveVocalResults(session: session, offset: page * 120),
              !Task.isCancelled, model.selected == session else { return }
        points = values
        if !values.contains(where: { $0.source == source }), let first = values.first { source = first.source }
        if !values.contains(where: { $0.id == selectedID }) { selectedID = values.first?.id }
    }
}
