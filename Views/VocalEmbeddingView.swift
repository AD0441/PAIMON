import LAICore
import SwiftUI

struct VocalEmbeddingView: View {
    var model: AppModel
    let report: VocalEmotionReport
    let source: AudioSource?
    @Binding var selection: Double?
    @State private var similarities: [VocalEmbeddingAnalysis.Similarity] = []
    @State private var changes: [VocalEmbeddingAnalysis.Change] = []
    @State private var error: String?

    private struct Request: Hashable {
        let session: UUID?
        let source: AudioSource?
        let selected: Double?
        let count: Int
        let threshold: Double
        let revision: UUID
    }
    private var selectedPoint: VocalEmotionPoint? {
        guard let selection else { return nil }
        return report.points.first { $0.start <= selection && selection < $0.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Label("Exploración de representaciones · experimental", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text("Un embedding es un vector que describe patrones acústicos de un intervalo. La similitud coseno compara esos patrones: 1 significa vectores iguales. No mide certeza ni intensidad de una emoción.")
                .foregroundStyle(.secondary)
            Text("\(report.model.title) · \(report.model.embeddingDimension ?? 0) componentes")
                .foregroundStyle(.secondary)
            Text("Estos vectores solo permanecen durante el análisis. No se guardan con la sesión.")
                .foregroundStyle(.secondary)
            if let error { Text(model.ui(error)).foregroundStyle(.secondary) }
            if selectedPoint?.embedding != nil {
                Text("Fragmentos con patrones vocales parecidos").fontWeight(.semibold)
                if similarities.isEmpty { Text("No hay otros intervalos comparables.") }
                ForEach(similarities) { value in
                    HStack {
                        Button(timestamp(value.id)) { selection = value.id }
                        Spacer()
                        Text("Similitud: \(value.value.formatted(.number.precision(.fractionLength(2))))").monospacedDigit()
                    }
                }
            } else {
                Text("Selecciona un intervalo con voz en el gráfico para comparar sus patrones.")
            }
            Text("Cambios entre intervalos analizados").fontWeight(.semibold)
            Text("Distancia coseno = 1 − similitud. El umbral configurable es exploratorio; un cambio puede deberse al hablante, el ruido, el micrófono o la expresión vocal.")
                .foregroundStyle(.secondary)
            if changes.isEmpty { Text("Sin cambios por encima del umbral en esta muestra.") }
            ForEach(changes) { value in
                HStack {
                    Button(timestamp(value.start)) { selection = value.start }
                    Text(model.ui(value.speakerChanged == true ? "Cambio de hablante"
                                  : value.speakerChanged == false ? "Cambio con el mismo hablante" : "Hablante sin determinar"))
                    Spacer()
                    Text(value.distance.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                }
            }
        }
        .font(.caption)
        .task(id: Request(session: model.selected, source: source, selected: selection, count: report.points.count,
                          threshold: model.settings.vocalChangeThreshold ?? 0.2, revision: model.sentimentRevision)) {
            await compare()
        }
    }

    private func compare() async {
        similarities = []; changes = []; error = nil
        guard !model.active, !model.pressure, let session = model.selected, let store = model.store, let source else { return }
        do {
            let segments = report.points.map {
                TranscriptSegment(sessionID: session, source: source, start: $0.start, end: $0.end, text: "")
            }
            let labels = try await store.speakers(for: segments, session: session)
            var speakers: [Double: String] = [:]
            for segment in segments {
                if let label = labels[segment.id] { speakers[segment.start] = label.id }
            }
            let found = try await VocalEmbeddingAnalysis.changes(in: report,
                threshold: model.settings.vocalChangeThreshold ?? 0.2, speakers: speakers)
            let similar: [VocalEmbeddingAnalysis.Similarity]
            if let point = selectedPoint { similar = try await VocalEmbeddingAnalysis.similar(to: point, in: report) }
            else { similar = [] }
            try Task.checkCancellation()
            guard model.selected == session else { return }
            changes = found; similarities = similar
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }
}
