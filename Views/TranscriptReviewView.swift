import LAICore
import SwiftUI

struct TranscriptReviewView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TranscriptReviewMode = .formal
    @State private var suggestions: [TranscriptReviewSuggestion] = []
    @State private var page = 0
    @State private var processed = 0
    @State private var work: Task<Void, Never>?
    @State private var working = false
    @State private var error: String?
    @State private var finished = false
    private var blocked: Bool { model.active || model.pressure || model.summaryWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Revisión inteligente", systemImage: "text.badge.checkmark").font(.title2.weight(.semibold))
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Apple Intelligence propone correcciones usando el contexto y el glosario. El original se conserva. Revisa cada propuesta antes de aceptarla.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Modo", selection: $mode) {
                ForEach(TranscriptReviewMode.allCases, id: \.self) { Text(model.ui($0.title)).tag($0) }
            }
            .disabled(working)
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("Fragmentos revisados: \(processed)").font(.caption)
                    Button("Cancelar") { work?.cancel() }
                } else {
                    Button("Revisar transcripción") { start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(blocked || model.selectedSession == nil || TranscriptReviewer.unavailableReason != nil)
                    Button("Aceptar propuestas de bajo riesgo") { acceptLowRisk() }
                        .help("Solo las propuestas mostradas de puntuación o mayúsculas que conservan las palabras.")
                        .disabled(blocked || !suggestions.contains { $0.state == .pending && $0.lowRisk })
                }
            }
            if let reason = TranscriptReviewer.unavailableReason {
                Text(model.ui(reason)).font(.caption).foregroundStyle(.secondary)
            }
            if blocked {
                Text("La revisión se pausa durante la captura, otros resúmenes o la presión de memoria.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(model.ui(error)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if finished { Text("Revisión terminada. No se aplicaron cambios automáticamente.").font(.caption) }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if suggestions.isEmpty {
                        Text("No hay sugerencias en esta página.").foregroundStyle(.secondary).padding(.vertical)
                    }
                    ForEach(suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(timestamp(suggestion.start)).monospacedDigit()
                                Text(model.ui(suggestion.kind.title))
                                Spacer()
                                Text(model.ui(stateTitle(suggestion.state)))
                            }.font(.caption).foregroundStyle(.secondary)
                            Text(suggestion.original).strikethrough(suggestion.original != suggestion.replacement)
                                .textSelection(.enabled)
                            if suggestion.original != suggestion.replacement {
                                Text(suggestion.replacement).fontWeight(.medium).textSelection(.enabled)
                            }
                            Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                            if suggestion.needsAudio {
                                Label("Comprueba el audio antes de corregir.", systemImage: "ear").font(.caption)
                            }
                            HStack {
                                Button("Aceptar") { accept(suggestion) }
                                    .disabled(blocked || working || suggestion.state != .pending || suggestion.original == suggestion.replacement)
                                Button("Rechazar") { reject(suggestion) }
                                    .disabled(working || suggestion.state != .pending)
                                Button("Escuchar fragmento") { Task { await model.playTranscriptReview(suggestion) } }
                                    .disabled(model.active || !(suggestion.source == .file || model.selectedSession?.settings.saveAudio == true))
                                Button("Ver transcripción") { Task { await model.revealTranscriptSegment(suggestion.segmentID); dismiss() } }
                            }.controlSize(.small)
                            Divider()
                        }
                    }
                }
            }
            HStack {
                Button("Anteriores") { page -= 1; Task { await reload() } }.disabled(page == 0 || working)
                Spacer()
                Button("Siguientes") { page += 1; Task { await reload() } }.disabled(suggestions.count < 50 || working)
            }.font(.caption)
        }
        .padding(24)
        .frame(width: 720, height: 660)
        .task(id: model.selected) { work?.cancel(); await reload() }
        .onChange(of: blocked) { _, value in if value { work?.cancel() } }
        .onDisappear { work?.cancel() }
    }

    private func stateTitle(_ state: TranscriptReviewSuggestion.State) -> String {
        switch state { case .pending: "Pendiente"; case .accepted: "Aceptada"; case .rejected: "Rechazada" }
    }

    private func reload() async {
        guard let session = model.selected, let store = model.store else { suggestions = []; return }
        do {
            let values = try await store.reviewSuggestions(session: session, offset: page * 50)
            guard model.selected == session else { return }
            suggestions = values
        } catch { self.error = error.localizedDescription }
    }

    private func start() {
        guard !blocked, !working, let session = model.selectedSession, let store = model.store else { return }
        working = true; processed = 0; finished = false; error = nil
        work = Task {
            defer { working = false; work = nil }
            do {
                try await TranscriptReviewer.review(session: session, store: store, mode: mode) { count in
                    await MainActor.run { processed = count }
                }
                try Task.checkCancellation()
                finished = true
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription }
            await reload()
        }
    }

    private func accept(_ suggestion: TranscriptReviewSuggestion) {
        guard !working, !blocked else { return }
        working = true
        work = Task {
            defer { working = false; work = nil }
            do { try await model.acceptTranscriptReview(suggestion) }
            catch { self.error = error.localizedDescription }
            await reload()
        }
    }

    private func reject(_ suggestion: TranscriptReviewSuggestion) {
        Task {
            do { try await model.store?.rejectReview(id: suggestion.id, session: suggestion.sessionID); await reload() }
            catch { self.error = error.localizedDescription }
        }
    }

    private func acceptLowRisk() {
        guard !working, !blocked else { return }
        let selected = suggestions.filter { $0.state == .pending && $0.lowRisk }
        working = true
        work = Task {
            defer { working = false; work = nil }
            do {
                for suggestion in selected {
                    try Task.checkCancellation()
                    try await model.acceptTranscriptReview(suggestion)
                }
            } catch is CancellationError {
            } catch { self.error = error.localizedDescription }
            await reload()
        }
    }
}
