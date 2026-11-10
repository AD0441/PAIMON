import Charts
import LAICore
import SwiftUI

struct SessionAnalysisPane: View {
    var model: AppModel
    @State private var selected: Tab = .summary
    private enum Tab: Hashable { case summary, sentiment, assistant }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección del informe", selection: $selected) {
                Text("Resumen").tag(Tab.summary)
                Text("Sentimientos").tag(Tab.sentiment)
                Text("Asistente").tag(Tab.assistant)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("sessionAnalysisTab")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            ZStack {
                SummaryView(model: model)
                    .opacity(selected == .summary ? 1 : 0)
                    .allowsHitTesting(selected == .summary)
                    .accessibilityHidden(selected != .summary)
                TranscriptAssistantView(model: model, visible: selected == .assistant)
                    .id(model.selected)
                    .opacity(selected == .assistant ? 1 : 0)
                    .allowsHitTesting(selected == .assistant)
                    .accessibilityHidden(selected != .assistant)
                if selected == .sentiment {
                    SentimentModes(model: model).id(model.selected)
                }
            }
        }
    }
}

private struct SentimentModes: View {
    var model: AppModel
    @State private var mode: Mode = .text
    private enum Mode: Hashable { case text, voice, mixed }

    var body: some View {
        if model.settings.vocalAnalysisEnabled == true {
            VStack(spacing: 0) {
                Picker("Tipo de análisis", selection: $mode) {
                    Text("Texto").tag(Mode.text)
                    Text("Voz").tag(Mode.voice)
                    Text("Mixto").tag(Mode.mixed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("sentimentMode")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                ZStack {
                    if mode == .text { SentimentView(model: model) }
                    VocalAnalysisView(model: model, visible: mode != .text, mixed: mode == .mixed)
                        .opacity(mode == .text ? 0 : 1)
                        .allowsHitTesting(mode != .text)
                        .accessibilityHidden(mode == .text)
                }
            }
        } else {
            SentimentView(model: model)
        }
    }
}

private struct SentimentView: View {
    var model: AppModel
    @Environment(\.locale) private var locale
    @State private var report: TranscriptSentiment?
    @State private var progress: Double?
    @State private var error: String?
    @State private var request = 0
    @State private var analyzeNext = false
    @State private var focused: Int?
    @State private var selectedEmotion: String?

    private struct Job: Hashable {
        var session: UUID?
        var revision: UUID
        var paused: Bool
        var request: Int
    }
    private var paused: Bool { model.active || model.pressure }
    private var job: Job {
        Job(session: model.selectedSession?.id, revision: model.sentimentRevision, paused: paused, request: request)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Análisis automatizado del lenguaje utilizado en la transcripción. Los resultados son orientativos y no representan una evaluación del estado emocional de las personas.")
                    .font(.caption).foregroundStyle(.secondary)
                if let progress {
                    ProgressView("Analizando transcripción…", value: progress)
                    Button("Cancelar análisis") {
                        analyzeNext = false
                        request += 1
                    }
                } else if model.selectedSession != nil {
                    Button {
                        analyzeNext = true
                        request += 1
                    } label: {
                        Label(model.ui(report == nil ? "Analizar sentimientos" : "Volver a analizar"), systemImage: "waveform.path")
                    }
                    .disabled(paused)
                    .accessibilityIdentifier("analyzeSentiment")
                    if paused {
                        Text(model.ui(model.active ? "Termina la captura o importación para analizar." : "El análisis se pausa mientras hay presión de memoria."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let report, !report.points.isEmpty {
                    reportContent(report)
                } else if progress == nil {
                    Text(model.ui(report == nil ? "Selecciona una sesión con transcripción para analizarla." : "Esta sesión no contiene texto para analizar."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: job) { await load() }
    }

    private func load() async {
        let currentJob = job
        let run = analyzeNext
        analyzeNext = false
        progress = nil
        error = nil
        focused = nil
        selectedEmotion = nil
        report = nil
        guard let session = model.selectedSession, let store = model.store else { return }
        do {
            if run && !paused {
                progress = 0
                let result = try await SentimentAnalyzer.analyze(session: session, store: store) { value in
                    await MainActor.run {
                        if job == currentJob { progress = value }
                    }
                }
                try Task.checkCancellation()
                guard job == currentJob else { return }
                report = result
            } else {
                let cached = try await store.cachedSentiment(session: session.id)
                try Task.checkCancellation()
                guard job == currentJob else { return }
                report = cached
            }
        } catch is CancellationError {
        } catch {
            if job == currentJob { self.error = error.localizedDescription }
        }
        if job == currentJob { progress = nil }
    }

    private func reportContent(_ report: TranscriptSentiment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Evolución de la polaridad").font(.headline)
            if report.points.contains(where: { $0.score != nil }) {
                Text("Cada punto muestra cómo Apple clasificó el tono de un fragmento. −1 es el extremo negativo, 0 es neutro y +1 es el extremo positivo.")
                    .font(.caption).foregroundStyle(.secondary)
                if let boundary = report.boundaryConcentration {
                    let value = boundary.score < 0 ? "−1" : "+1"
                    Label("\(boundary.count) de \(boundary.total) fragmentos puntuados quedaron en \(value). Apple devolvió el mismo extremo para la mayoría. Lee las citas para comprobar el tono en contexto.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let selected = focused.flatMap { report.points.indices.contains($0) ? report.points[$0] : nil }
                SentimentChart(report: report, selection: selected.map { position($0, timed: report.usesTime) }) { value in
                    let timed = report.usesTime
                    focused = report.points.lazy.filter { $0.score != nil }.min {
                        abs(position($0, timed: timed) - value) < abs(position($1, timed: timed) - value)
                    }?.id
                }
                Text("Haz clic en el gráfico para fijar un momento.").font(.caption).foregroundStyle(.secondary)
                if let focused, report.points.indices.contains(focused) {
                    let point = report.points[focused]
                    VStack(alignment: .leading, spacing: 8) {
                        pointContent(point)
                        HStack {
                            Button { self.focused = max(0, focused - 1) } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Fragmento anterior").disabled(focused == 0)
                            Button { self.focused = min(report.points.count - 1, focused + 1) } label: { Image(systemName: "chevron.right") }
                                .accessibilityLabel("Fragmento siguiente").disabled(focused == report.points.count - 1)
                        }
                    }
                }
                let unscored = report.points.filter { $0.score == nil }.count
                if unscored > 0 {
                    Text("\(unscored) fragmentos sin puntuación de Apple.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("NaturalLanguage no devolvió puntuaciones para esta transcripción.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Emociones expresadas").font(.headline)
            Text("Apple Intelligence asigna etiquetas al lenguaje de los fragmentos. Por ejemplo, «preocupación» señala una expresión de inquietud. El número indica en cuántos fragmentos apareció cada etiqueta.")
                .font(.caption).foregroundStyle(.secondary)
            switch report.tagging {
            case .unavailable: Text("La clasificación de emociones requiere Apple Intelligence disponible en este Mac.")
            case .unsupported: Text("Apple Intelligence no admite el idioma de los fragmentos seleccionados.")
            case .partial: Text("Apple Intelligence devolvió un análisis parcial.")
            case .complete: EmptyView()
            }
            if report.tagged > 0 {
                Text("Emociones analizadas en \(report.tagged) de \(report.points.count) fragmentos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if report.emotionCounts.isEmpty, report.tagged > 0 {
                Text("Sin etiquetas emocionales en los fragmentos analizados.").font(.caption).foregroundStyle(.secondary)
            }
            if !report.emotionCounts.isEmpty {
                Text("Selecciona una etiqueta para leer los fragmentos asociados.").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(report.emotionCounts, id: \.tag) { item in
                        Button {
                            selectedEmotion = selectedEmotion == item.tag ? nil : item.tag
                        } label: {
                            Label("\(item.tag) · \(item.count)",
                                  systemImage: selectedEmotion == item.tag ? "checkmark" : "tag")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityAddTraits(selectedEmotion == item.tag ? .isSelected : [])
                    }
                }
                if let selectedEmotion {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Fragmentos con «\(selectedEmotion)»").font(.subheadline.weight(.semibold))
                        ForEach(report.points.filter { $0.emotions.contains(selectedEmotion) }) { point in
                            pointContent(point)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Divider()
            Text("Momentos destacados").font(.headline)
            let threshold = TranscriptSentiment.changeThreshold.formatted(.number.locale(locale).precision(.fractionLength(2)))
            Text("Un cambio de polaridad es una diferencia de al menos \(threshold) entre dos fragmentos consecutivos con puntaje. Puede ocurrir aunque ambos puntajes tengan el mismo signo.")
                .font(.caption).foregroundStyle(.secondary)
            let moments = report.moments()
            if moments.isEmpty { Text("Sin momentos destacados con los datos disponibles.").font(.caption).foregroundStyle(.secondary) }
            ForEach(moments) { moment in
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(moment.reason)).font(.subheadline.weight(.semibold))
                    if let previous = moment.previousScore, let current = moment.point.score {
                        let format = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(2))
                        Text("Puntaje anterior \(previous.formatted(format)) → actual \(current.formatted(format))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    pointContent(moment.point)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func position(_ point: SentimentPoint, timed: Bool) -> Double {
        timed ? point.time ?? 0 : Double(point.id + 1)
    }

    private func title(_ reason: TranscriptSentiment.Moment.Reason) -> LocalizedStringKey {
        switch reason {
        case .positive: "Polaridad positiva destacada"
        case .negative: "Polaridad negativa destacada"
        case .change: "Cambio de polaridad"
        case .topicChange: "Cambio de polaridad sobre el mismo tema"
        case .emotion: "Emoción expresada"
        }
    }

    private func pointContent(_ point: SentimentPoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if let time = point.time, report?.usesTime == true {
                    Text(timestamp(time)).monospacedDigit()
                } else { Text("Fragmento \(point.id + 1)") }
                if let speaker = point.speaker { Text(speaker) }
                else if let number = point.speakerNumber { Text("Hablante \(number)") }
                Spacer()
                if let score = point.score {
                    Text(score, format: .number.precision(.fractionLength(2))).monospacedDigit()
                }
            }.font(.caption).foregroundStyle(.secondary)
            Text("«\(point.excerpt)»").textSelection(.enabled)
            if !point.emotions.isEmpty {
                Label(point.emotions.joined(separator: " · "), systemImage: "tag").font(.caption)
            }
            if !point.context.isEmpty {
                Label(point.context.joined(separator: " · "), systemImage: "text.bubble")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Ir a la transcripción") { Task { await model.revealTranscriptSegment(point.segmentID) } }
                .buttonStyle(.link).font(.caption)
        }
    }
}

private struct SentimentChart: View {
    var report: TranscriptSentiment
    var selection: Double?
    var select: (Double) -> Void

    var body: some View {
        let timed = report.usesTime
        let lower = report.points.first.map { position($0, timed: timed) } ?? 0
        let upper = max(lower + 1, report.points.last.map { position($0, timed: timed) } ?? 0)
        let samples = plotSamples(timed: timed)
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                RectangleMark(xStart: .value("Inicio", lower), xEnd: .value("Fin", upper),
                              yStart: .value("Polaridad", 0.2), yEnd: .value("Polaridad", 1.0))
                    .foregroundStyle(Color.green.opacity(0.08))
                RectangleMark(xStart: .value("Inicio", lower), xEnd: .value("Fin", upper),
                              yStart: .value("Polaridad", -0.2), yEnd: .value("Polaridad", 0.2))
                    .foregroundStyle(Color.secondary.opacity(0.08))
                RectangleMark(xStart: .value("Inicio", lower), xEnd: .value("Fin", upper),
                              yStart: .value("Polaridad", -1.0), yEnd: .value("Polaridad", -0.2))
                    .foregroundStyle(Color.orange.opacity(0.10))
                RuleMark(y: .value("Referencia", 0))
                    .foregroundStyle(Color.secondary)
                LinePlot(samples, x: .value("Momento", \.position), y: .value("Polaridad", \.score),
                         series: .value("Tramo", \.group))
                    .foregroundStyle(Color.accentColor)
                PointPlot(samples, x: .value("Momento", \.position), y: .value("Polaridad", \.score))
                    .foregroundStyle(Color.accentColor).symbolSize(18)
                if let selection {
                    RuleMark(x: .value("Selección", selection)).foregroundStyle(Color.secondary)
                }
            }
            .chartXScale(domain: lower...upper)
            .chartYScale(domain: -1.0...1.0)
            .chartYAxis { AxisMarks(values: [-1.0, 0.0, 1.0]) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let x = value.as(Double.self) {
                            if timed { Text(String(format: "%02d:%02d", Int(x)/60, Int(x)%60)) }
                            else if x.rounded() == x { Text(Int(x), format: .number) }
                        }
                    }
                }
            }
            .pinChartSelection(select)
            .frame(height: 190)
            .accessibilityLabel("Evolución de la polaridad")
            HStack(spacing: 10) {
                Label("Positiva", systemImage: "plus.circle")
                Text("Neutra")
                Label("Negativa", systemImage: "minus.circle")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private struct Sample {
        let position: Double
        let score: Double
        let group: Int
    }

    private func position(_ point: SentimentPoint, timed: Bool) -> Double {
        timed ? point.time ?? 0 : Double(point.id + 1)
    }

    private func plotSamples(timed: Bool) -> [Sample] {
        var group = 0
        return report.points.compactMap { point in
            guard let score = point.score else { group += 1; return nil }
            return Sample(position: position(point, timed: timed), score: score, group: group)
        }
    }
}


extension View {
    /// Only a click inside the plot changes the selection. Leaving the chart
    /// keeps the selected interval and its controls available.
    func pinChartSelection(_ select: @escaping (Double) -> Void) -> some View {
        pinChartSelection { time, _ in select(time) }
    }

    /// The second value is the time covered by three points around the click.
    func pinChartSelection(_ select: @escaping (Double, Double) -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        let x = tap.location.x - frame.minX
                        guard frame.contains(tap.location),
                              let time = proxy.value(atX: x, as: Double.self),
                              time.isFinite else { return }
                        let nearbyX = x + (x + 3 < frame.width ? 3 : -3)
                        let nearbyTime = proxy.value(atX: nearbyX, as: Double.self) ?? time
                        select(time, abs(nearbyTime - time))
                    })
            }
            .accessibilityHidden(true)
        }
    }
}
