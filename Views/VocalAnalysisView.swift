import Charts
import LAICore
import SwiftUI

struct VocalAnalysisView: View {
    var model: AppModel
    let visible: Bool
    let mixed: Bool
    @State private var tracks: [VocalAudioTrack] = []
    @State private var source: AudioSource?
    @State private var metric: Metric = .level
    @State private var points: [VocalPoint] = []
    @State private var emotionReport: VocalEmotionReport?
    @State private var textReport: TranscriptSentiment?
    @State private var mixedTime: Double?
    @State private var time: Double?
    @State private var segment: TranscriptSegment?
    @State private var progress = 0.0
    @State private var running: Analysis?
    @State private var soundReport: VocalSoundReport?
    @State private var shownEvents = 12
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var generation = UUID()

    private struct AudioRequest: Equatable {
        let revision: UUID
        let capturing: Bool
        let visible: Bool
    }

    private struct EvidenceRequest: Equatable {
        let time: Double?
        let mixed: Bool
        let revision: UUID
    }

    private enum Analysis {
        case measurements, sounds, mixed
    }

    private enum Metric: Hashable {
        case level, pitch, quiet

        var domain: ClosedRange<Double> {
            switch self {
            case .level: -80...0
            case .pitch: 60...500
            case .quiet: 0...100
            }
        }

        func value(_ point: VocalPoint) -> Double? {
            switch self {
            case .level: point.level
            case .pitch: point.pitch
            case .quiet: point.quietPercent
            }
        }
    }

    private var paused: Bool { model.active || model.pressure }
    private var emotionEnabled: Bool {
        model.settings.vocalEmotionEnabled == true && model.installedModels.contains((model.settings.vocalEmotionModel ?? .base).package)
    }

    private var emotionPoint: VocalEmotionPoint? {
        guard let mixedTime else { return nil }
        return emotionReport?.points.first { $0.start <= mixedTime && mixedTime < $0.end }
    }

    private var track: VocalAudioTrack? { tracks.first { $0.source == source } }
    private var point: VocalPoint? {
        guard let time else { return nil }
        return points.first { $0.start <= time && time < $0.end }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if mixed {
                    Label("Texto y emociones de voz", systemImage: "waveform.and.text").font(.headline)
                    Text("Compara la polaridad del texto con las etiquetas del modelo vocal seleccionado. Las estimaciones vocales son experimentales.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Análisis vocal", systemImage: "waveform").font(.headline)
                    Text("Mide cambios audibles de intensidad, altura y pausas. Las mediciones describen la señal grabada.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if paused {
                    Text(model.ui(model.active ? "Termina la captura o importación para analizar." : "El análisis se pausa mientras hay presión de memoria."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if tracks.isEmpty {
                    unavailable
                } else if mixed && !emotionEnabled {
                    Text("Descarga o activa el modelo seleccionado en Ajustes → Modelos → Emociones de voz.")
                        .font(.callout).foregroundStyle(.secondary)
                    SettingsLink { Text("Abrir Ajustes") }
                } else {
                    controls
                }
                if let error {
                    Label(model.ui(error), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if mixed {
                    if let emotionReport, emotionEnabled { mixedResults(emotionReport) }
                } else {
                    if let soundReport { soundResults(soundReport) }
                    if !points.isEmpty { results }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: AudioRequest(revision: model.audioLinkRevision, capturing: model.active, visible: visible)) {
            if visible && !model.active { await loadTracks() }
        }
        .task(id: EvidenceRequest(time: mixed ? mixedTime : point?.start, mixed: mixed, revision: model.sentimentRevision)) { await loadEvidence() }
        .onChange(of: source) { reset() }
        .onChange(of: model.settings.vocalEmotionModel) { reset() }
        .onChange(of: model.settings.vocalEmbeddingsEnabled) { reset() }
        .onChange(of: mixed) { cancel(); error = nil }
        .onChange(of: emotionEnabled) { _, enabled in
            if !enabled {
                if running == .mixed { cancel() }
                emotionReport = nil
                textReport = nil
                mixedTime = nil
            }
        }
        .onChange(of: model.sentimentRevision) {
            if running == .mixed { cancel() }
            textReport = nil
        }
        .onChange(of: model.audioLinkRevision) { reset() }
        .onChange(of: model.vocalSoundIdentifiers) {
            if running == .sounds { cancel() }
            soundReport = nil
        }
        .onChange(of: paused) { _, value in
            if value { cancel() }
        }
        .onChange(of: visible) { _, value in if !value { cancel() } }
        .onDisappear { cancel() }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.selectedSession == nil {
                Text("Selecciona una sesión con audio para analizar la voz.")
            } else if model.selectedSession?.importedFileName != nil {
                Text("Vincula el archivo original para analizar la voz de esta sesión.")
                Button("Vincular audio original") {
                    Task { await model.linkOriginalAudio() }
                }
            } else {
                Text("Esta sesión no conserva audio. Para futuras capturas, activa «Guardar audio de próximas sesiones» en Ajustes.")
            }
        }
        .font(.callout).foregroundStyle(.secondary)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if tracks.count > 1 {
                Picker("Pista de audio", selection: $source) {
                    ForEach(tracks) { track in
                        Text(model.ui(track.source.title)).tag(Optional(track.source))
                    }
                }
                .disabled(running != nil)
            }
            if let running {
                switch running {
                case .measurements:
                    ProgressView("Analizando la voz…", value: progress)
                case .sounds:
                    ProgressView("Buscando eventos audibles…")
                case .mixed:
                    ProgressView("Analizando texto y emociones de voz…", value: progress)
                }
                Button("Cancelar análisis", action: cancel)
            } else if mixed {
                Button { analyze(.mixed) } label: {
                    Label("Analizar texto y voz", systemImage: "waveform")
                }
                .disabled(track == nil || model.vocalEmotionWorking)
                .accessibilityIdentifier("analyzeMixedSentiment")
            } else {
                Button { analyze(.measurements) } label: {
                    Label(model.ui(points.isEmpty ? "Analizar voz" : "Volver a analizar"), systemImage: "waveform.path")
                }
                .disabled(track == nil)
                .accessibilityIdentifier("analyzeVoice")
                Button { analyze(.sounds) } label: {
                    Label("Buscar sonidos seleccionados", systemImage: "waveform.badge.magnifyingglass")
                }
                .disabled(track == nil || model.vocalSoundIdentifiers.isEmpty)
                .accessibilityIdentifier("findVocalSounds")
                if model.vocalSoundIdentifiers.isEmpty {
                    Text("Selecciona sonidos en Ajustes → Modelos → Análisis vocal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.selectedSession?.importedFileName != nil {
                    Button("Vincular audio original") {
                        Task { await model.linkOriginalAudio() }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func soundResults(_ report: VocalSoundReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eventos audibles").font(.headline)
            Text("Sound Analysis de Apple marca intervalos de las categorías que seleccionaste. Escúchalos para comprobar el resultado.")
                .font(.caption).foregroundStyle(.secondary)
            if report.events.isEmpty {
                Text("No se detectaron los sonidos seleccionados en esta pista.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(report.events.prefix(shownEvents)) { event in
                VStack(alignment: .leading, spacing: 5) {
                    Label(model.ui(event.kind.title), systemImage: event.kind.symbol)
                        .font(.callout.weight(.semibold))
                    Text("\(timestamp(event.start)) a \(timestamp(event.end))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    HStack {
                        if let track {
                            playbackButton(track, start: event.audioStart, end: event.audioEnd)
                        }
                        Button("Ir a la transcripción") {
                            Task { await revealSound(event) }
                        }
                        .disabled(paused)
                    }
                    .controlSize(.small)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("vocalSoundEvent-\(event.id)")
            }
            if shownEvents < report.events.count {
                Button("Mostrar más eventos") { shownEvents += 12 }
            }
            if report.limited {
                Text("Se muestran los primeros eventos de la pista.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealSound(_ event: VocalSoundEvent) async {
        guard let source, let session = model.selectedSession, let store = model.store else { return }
        do {
            let match = try await store.overlappingSegment(session: session.id, source: source, from: event.start, to: event.end)
            guard model.selected == session.id, self.source == source else { return }
            if let match {
                error = nil
                await model.revealTranscriptSegment(match.id)
            } else {
                error = "No hay un fragmento de transcripción en este intervalo."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func playbackButton(_ track: VocalAudioTrack, start: Double, end: Double) -> some View {
        Button(model.ui(model.importedPlayback.isPlaying ? "Detener reproducción" : "Escuchar intervalo")) {
            if model.importedPlayback.isPlaying {
                model.importedPlayback.stop()
            } else {
                Task {
                    do { try await model.importedPlayback.play(track.url, start: start, end: end) }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .disabled(paused)
    }

    private var results: some View {
        let selected = point
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Medición vocal", selection: $metric) {
                Text("Intensidad").tag(Metric.level)
                Text("Altura").tag(Metric.pitch)
                Text("Pausas").tag(Metric.quiet)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch metric {
            case .level:
                Text("Nivel en dBFS. Los valores cercanos a cero corresponden a una señal más intensa.")
            case .pitch:
                Text("Frecuencia fundamental estimada en Hz. Se muestra cuando hay una señal periódica clara.")
            case .quiet:
                Text("Porcentaje del intervalo medido con señal de nivel bajo (−46 dBFS o menos).")
            }
            if points.contains(where: { metric.value($0) != nil }) {
                Chart {
                    ForEach(points) { point in
                        if let value = metric.value(point) {
                            PointMark(x: .value("Tiempo", point.start), y: .value("Medición", value))
                                .symbolSize(selected?.id == point.id ? 48 : 15)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Intervalo", selected.start))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .chartYScale(domain: metric.domain)
                .chartXScale(domain: 0...max(1, points.last?.end ?? 1, model.selectedSession?.duration ?? 0))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) { Text(timestamp(seconds)).monospacedDigit() }
                        }
                    }
                }
                .pinChartSelection { value in
                    if points.contains(where: { $0.start <= value && value < $0.end }) { time = value }
                }
                .frame(height: 160)
                .accessibilityLabel("Mediciones vocales por tiempo")
                Text("Haz clic en el gráfico para fijar un momento.")
                if let selected { details(selected) }
            } else {
                Text("No se pudo estimar la altura en esta pista.")
            }
        }
        .font(.caption)
    }

    private func mixedResults(_ report: VocalEmotionReport) -> some View {
        let sourcePrefix = (source?.rawValue ?? "") + "-"
        let marks = (textReport?.points ?? []).compactMap { point -> MixedTimeline.TextMark? in
            guard point.segmentID.hasPrefix(sourcePrefix), let time = point.time, let score = point.score else { return nil }
            return .init(id: point.id, time: time, score: score)
        }
        let step = max(1, (marks.count + 899) / 900)
        let plotted = stride(from: 0, to: marks.count, by: step).map { marks[$0] }
        let duration = max(1, model.selectedSession?.duration ?? 0, report.points.last?.end ?? 0, marks.map(\.time).max() ?? 0)
        let present = Set(report.points.map(\.emotion))
        let emotions: [VocalEmotion?] = VocalEmotion.allCases.map(Optional.some).filter { present.contains($0) }
            + (present.contains(nil) ? [nil] : [])
        let rows = Dictionary(uniqueKeysWithValues: emotions.enumerated().map { ($0.element, $0.offset) })
        let labels = emotions.map { model.ui($0?.title ?? "Sin etiqueta") }
        let voice = report.points.compactMap { point -> MixedTimeline.VoiceMark? in
            guard let row = rows[point.emotion] else { return nil }
            return .init(id: point.id, start: point.start, end: point.end, row: row, classified: point.emotion != nil)
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text(report.model.title).font(.caption).foregroundStyle(.secondary)
            MixedTimeline(text: plotted, voice: voice, labels: labels, duration: duration, selection: $mixedTime)
            if report.sampled {
                Text("En esta sesión se analizó una muestra de intervalos de voz.").foregroundStyle(.secondary)
            }
            Text("Haz clic en el gráfico para fijar un momento.").foregroundStyle(.secondary)
            if let mixedTime { mixedDetails(at: mixedTime) }
            if report.points.contains(where: { $0.embedding != nil }) {
                VocalEmbeddingView(model: model, report: report, source: source, selection: $mixedTime)
            }
        }
        .font(.caption)
    }

    private func mixedDetails(at time: Double) -> some View {
        let matches = textReport?.points.filter { $0.segmentID == segment?.id } ?? []
        let text = matches.first(where: { $0.score != nil || !$0.emotions.isEmpty }) ?? matches.first
        return VStack(alignment: .leading, spacing: 6) {
            Text(timestamp(time)).font(.caption.weight(.semibold)).monospacedDigit()
            if let score = text?.score {
                Text("Polaridad del texto: \(score.formatted(.number.precision(.fractionLength(2))))")
            }
            if let text, !text.emotions.isEmpty { Text(text.emotions.joined(separator: " · ")) }
            if let segment {
                Button("Ir a la transcripción") { Task { await model.revealTranscriptSegment(segment.id) } }
            }
            if let point = emotionPoint {
                if let emotion = point.emotion {
                    Text("Voz · \(model.ui(emotion.title))")
                    if let confidence = point.confidence {
                        Text("Puntuación del modelo: \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Voz · Sin etiqueta")
                }
                if let track {
                    playbackButton(track, start: point.audioStart, end: point.audioEnd)
                }
            } else {
                Text("Sin intervalo de voz analizado en este momento.").foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("mixedSelectionDetails")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ point: VocalPoint) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(timestamp(point.start)) a \(timestamp(point.end))")
                .font(.caption.weight(.semibold)).monospacedDigit()
            Text("Intensidad: \(point.level.formatted(.number.precision(.fractionLength(1)))) dBFS")
            if let pitch = point.pitch {
                Text("Altura estimada: \(pitch.formatted(.number.precision(.fractionLength(0)))) Hz")
            }
            if let variation = point.pitchVariation {
                Text("Variación tonal: \(variation.formatted(.number.precision(.fractionLength(0)))) Hz")
            }
            Text("Tiempo de nivel bajo: \(point.quietSeconds.formatted(.number.precision(.fractionLength(1)))) s")
            if let segment {
                let duration = segment.end - segment.start
                if duration >= 1 {
                    let rate = Double(segment.text.split(whereSeparator: \.isWhitespace).count) * 60 / duration
                    Text("Ritmo estimado del fragmento: \(rate.formatted(.number.precision(.fractionLength(0)))) palabras/min")
                }
                Button("Ir a la transcripción") {
                    Task { await model.revealTranscriptSegment(segment.id) }
                }
            }
            if let track, point.audioEnd > point.audioStart {
                playbackButton(track, start: point.audioStart, end: point.audioEnd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadTracks() async {
        guard let session = model.selectedSession, let store = model.store else { return }
        do {
            var available: [VocalAudioTrack]
            if session.importedFileName != nil {
                available = []
                if let data = try await store.audioBookmark(session: session.id),
                   let url = try? ImportedAudioPlayback.resolve(data) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if FileManager.default.isReadableFile(atPath: url.path) {
                        available = [VocalAudioTrack(importedAudio: url)]
                    }
                }
            } else {
                let directory = await store.directory
                available = VocalAudioTrack.archived(in: directory.appendingPathComponent(session.id.uuidString))
            }
            guard !Task.isCancelled, model.selected == session.id else { return }
            tracks = available
            if !tracks.contains(where: { $0.source == source }) { source = tracks.first?.source }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadEvidence() async {
        segment = nil
        guard let source, let session = model.selectedSession, let store = model.store else { return }
        let start: Double
        let end: Double
        if mixed, let mixedTime {
            start = mixedTime
            end = mixedTime + 0.001
        } else if !mixed, let point {
            start = point.start
            end = point.end
        } else { return }
        do {
            let match = try await store.overlappingSegment(session: session.id, source: source, from: start, to: end)
            guard !Task.isCancelled else { return }
            segment = match
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func analyze(_ analysis: Analysis) {
        guard visible, !paused, request == nil, let track, let session = model.selectedSession else { return }
        let token = UUID()
        generation = token
        error = nil
        progress = 0
        running = analysis
        request = Task(priority: .utility) {
            do {
                switch analysis {
                case .measurements:
                    let result = try await VocalAnalysis.analyze(track: track, sessionDuration: session.duration) { fraction in
                        await MainActor.run {
                            if generation == token { progress = fraction }
                        }
                    }
                    guard !Task.isCancelled, generation == token, model.selected == session.id else { return }
                    points = result
                    time = result.first?.start
                    if result.isEmpty { error = "No hay intervalos de audio disponibles para analizar." }
                case .sounds:
                    let result = try await VocalSoundAnalysis.analyze(track: track, sessionDuration: session.duration,
                                                                     identifiers: model.vocalSoundIdentifiers)
                    guard !Task.isCancelled, generation == token, model.selected == session.id else { return }
                    shownEvents = 12
                    soundReport = result
                case .mixed:
                    guard emotionEnabled, !model.vocalEmotionWorking, let store = model.store else {
                        running = nil
                        request = nil
                        return
                    }
                    let voice = try await analyzeEmotion(track, duration: session.duration, token: token)
                    guard !Task.isCancelled, generation == token, model.selected == session.id else { return }
                    emotionReport = voice
                    mixedTime = voice.points.first(where: { $0.emotion != nil })?.start ?? voice.points.first?.start
                    if let cached = try await store.cachedSentiment(session: session.id) {
                        guard !Task.isCancelled, generation == token else { return }
                        textReport = cached
                    } else {
                        let text = try await SentimentAnalyzer.analyze(session: session, store: store) { fraction in
                            await MainActor.run {
                                if generation == token { progress = 0.55 + fraction * 0.45 }
                            }
                        }
                        guard !Task.isCancelled, generation == token else { return }
                        textReport = text
                    }
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                self.error = error.localizedDescription
            }
            running = nil
            request = nil
        }
    }

    private func analyzeEmotion(_ track: VocalAudioTrack, duration: Double, token: UUID) async throws -> VocalEmotionReport {
        model.vocalEmotionWorking = true
        defer { model.vocalEmotionWorking = false }
        return try await VocalEmotionAnalysis.analyze(track: track, sessionDuration: duration,
            choice: model.settings.vocalEmotionModel ?? .base, embeddings: model.settings.vocalEmbeddingsEnabled == true) { fraction in
            await MainActor.run {
                if generation == token { progress = fraction * 0.55 }
            }
        }
    }

    private func reset() {
        cancel()
        points = []
        emotionReport = nil
        textReport = nil
        mixedTime = nil
        soundReport = nil
        time = nil
        segment = nil
        error = nil
    }

    private func cancel() {
        generation = UUID()
        request?.cancel()
        request = nil
        running = nil
    }
}

private struct MixedTimeline: View {
    struct TextMark: Identifiable {
        let id: Int
        let time: Double
        let score: Double
    }

    struct VoiceMark: Identifiable {
        let id: Double
        let start: Double
        let end: Double
        let row: Int
        let classified: Bool

        var midpoint: Double { start + (end - start) / 2 }
    }

    let text: [TextMark]
    let voice: [VoiceMark]
    let labels: [String]
    let duration: Double
    @Binding var selection: Double?

    private let labelWidth: CGFloat = 82
    private let gutter: CGFloat = 10
    private let edgeInset: CGFloat = 3
    private let voiceRowHeight: CGFloat = 23
    private let polarityInset: CGFloat = 8

    private var ticks: [Double] {
        let interior = (1...3).map { (duration * Double($0) / 4).rounded() }
        let distinct = Set(interior.filter { $0 > 0 && $0 < duration.rounded(.down) })
        return [0] + distinct.sorted() + [duration]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Polaridad del texto · −1 a +1").font(.headline)
            if text.isEmpty {
                Text("Esta pista no tiene polaridad textual disponible.").foregroundStyle(.secondary)
            } else {
                chartRow {
                    VStack(spacing: 0) {
                        axisLabel("+1").frame(height: polarityInset * 2)
                        Spacer(minLength: 0)
                        axisLabel("0").frame(height: polarityInset * 2)
                        Spacer(minLength: 0)
                        axisLabel("−1").frame(height: polarityInset * 2)
                    }
                    .monospacedDigit()
                } plot: {
                    plot {
                        ForEach([-1.0, 0, 1], id: \.self) { value in
                            RuleMark(y: .value("Polaridad", value))
                                .foregroundStyle(Color.secondary.opacity(value == 0 ? 0.45 : 0.2))
                        }
                        ForEach(text) { mark in
                            PointMark(x: .value("Tiempo", mark.time), y: .value("Polaridad", mark.score))
                                .foregroundStyle(.orange)
                                .symbolSize(22)
                        }
                    }
                    .chartYScale(domain: -1.0...1.0, range: .plotDimension(padding: polarityInset))
                    .pinChartSelection { time in
                        selection = text.min { abs($0.time - time) < abs($1.time - time) }?.time
                    }
                    .accessibilityIdentifier("mixedTextChart")
                }
                .frame(height: 112)
            }

            Text("Emociones estimadas de la voz").font(.headline)
            if voice.isEmpty {
                Text("No hay intervalos de audio disponibles para analizar.").foregroundStyle(.secondary)
            } else {
                chartRow {
                    VStack(spacing: 0) {
                        ForEach(labels.indices, id: \.self) { row in
                            axisLabel(labels[row]).frame(height: voiceRowHeight)
                        }
                    }
                } plot: {
                    plot {
                        ForEach(labels.indices, id: \.self) { row in
                            RuleMark(y: .value("Fila", voiceY(row)))
                                .foregroundStyle(Color.secondary.opacity(0.2))
                        }
                        ForEach(voice) { mark in
                            PointMark(x: .value("Tiempo", mark.midpoint), y: .value("Fila", voiceY(mark.row)))
                                .foregroundStyle(mark.classified ? Color.accentColor : .secondary.opacity(0.4))
                                .symbolSize(20)
                                .accessibilityLabel(Text(labels[mark.row]))
                                .accessibilityValue(Text(timestamp(mark.midpoint)))
                        }
                    }
                    .chartYScale(domain: 0...Double(labels.count), range: .plotDimension)
                    .pinChartSelection { time, tolerance in
                        let nearest = voice.min { abs($0.midpoint - time) < abs($1.midpoint - time) }
                        if let nearest, abs(nearest.midpoint - time) <= tolerance {
                            selection = nearest.midpoint
                        } else {
                            selection = min(max(0, time), duration)
                        }
                    }
                    .accessibilityIdentifier("mixedVoiceChart")
                }
                .frame(height: CGFloat(labels.count) * voiceRowHeight)
            }

            if !text.isEmpty || !voice.isEmpty {
                chartRow {
                    Color.clear
                } plot: {
                    timeAxis
                }
                .frame(height: 16)
            }
        }
    }

    private func voiceY(_ row: Int) -> Double { Double(labels.count - row) - 0.5 }

    private func axisLabel(_ label: String) -> some View {
        Text(label)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // Both panels and the clock use the same gutter and insets. Native axis
    // labels would reserve different horizontal space for each chart.
    private func chartRow<Labels: View, Plot: View>(
        @ViewBuilder labels: () -> Labels, @ViewBuilder plot: () -> Plot
    ) -> some View {
        HStack(spacing: gutter) {
            labels().frame(width: labelWidth)
            plot().frame(maxWidth: .infinity)
        }
    }

    private func plot<Marks: ChartContent>(@ChartContentBuilder _ marks: () -> Marks) -> some View {
        Chart {
            ForEach(ticks, id: \.self) { time in
                RuleMark(x: .value("Tiempo", time))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            marks()
            if let selection {
                RuleMark(x: .value("Selección", selection))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: 0...duration, range: .plotDimension(padding: edgeInset))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private var timeAxis: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clockWidth: CGFloat = 64
            let times = ticks
            let visible = width >= clockWidth * 5 ? times
                : width >= clockWidth * 3 && times.count == 5 ? [0, times[2], duration]
                : width >= clockWidth * 2 ? [0, duration] : [0]
            ForEach(visible, id: \.self) { time in
                let x = edgeInset + (width - 2 * edgeInset) * time / duration
                Text(timestamp(time))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: clockWidth, alignment: time == 0 ? .leading : time == duration ? .trailing : .center)
                    .position(x: time == 0 ? x + clockWidth / 2 : time == duration ? x - clockWidth / 2 : x,
                              y: geometry.size.height / 2)
            }
        }
    }
}
