import LAICore
import SwiftUI

struct TranscriptAssistantView: View {
    var model: AppModel
    let visible: Bool
    @State private var question = ""
    @State private var turns: [Turn] = []
    @State private var pending: String?
    @State private var job: Task<Void, Never>?
    @State private var request = UUID()
    @State private var problem: String?
    @State private var unavailable: String?

    private struct Turn: Identifiable {
        let id = UUID()
        let question: String
        let reply: TranscriptAssistantReply
    }

    private var paused: Bool { model.active || model.pressure }
    private var canAsk: Bool {
        model.selectedSession != nil && model.store != nil && !paused && unavailable == nil &&
            pending == nil && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Asistente local", systemImage: "bubble.left.and.text.bubble.right").font(.headline)
                Text("Haz preguntas sobre la transcripción. El asistente usa Apple Intelligence en este Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            conversation
            Divider()
            composer
        }
        .task(id: visible) {
            if visible { unavailable = TranscriptAssistant.availability() }
        }
        .onChange(of: visible) { _, value in
            if !value { cancel(restore: true) }
        }
        .onChange(of: paused) { _, value in
            if value { cancel(restore: true) }
        }
        .onChange(of: model.sentimentRevision) {
            cancel(restore: true)
            turns.removeAll()
            problem = nil
        }
        .onDisappear { cancel(restore: false) }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let pending, turns.isEmpty {
                        Text(pending).font(.callout.weight(.semibold)).textSelection(.enabled)
                    } else if turns.isEmpty {
                        if model.selectedSession == nil {
                            Text("Selecciona una sesión para hacer preguntas.")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Por ejemplo, «¿Qué se decidió?» o «¿Qué tareas quedaron pendientes?»")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(turns) { turn in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(turn.question).font(.callout.weight(.semibold)).textSelection(.enabled)
                            if let answer = turn.reply.text {
                                Text(answer).textSelection(.enabled)
                            } else {
                                Text("No encontré una respuesta respaldada en los fragmentos consultados.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(turn.reply.evidence, id: \.self) { source in
                                Button {
                                    Task { await model.revealTranscriptSegment(source.segmentID) }
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Image(systemName: "quote.bubble")
                                        if source.start.isFinite, source.start >= 0, source.start < Double(Int.max) {
                                            Text(timestamp(source.start)).monospacedDigit()
                                        }
                                        Text(source.quote).lineLimit(2)
                                    }
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.link)
                                .help("Ir a la transcripción")
                                .accessibilityIdentifier("assistantEvidence")
                            }
                            if turn.reply.sampled {
                                Text("Se consultó una parte de la transcripción.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .id(turn.id)
                        if turn.id != turns.last?.id || pending != nil { Divider() }
                    }
                    if let pending, !turns.isEmpty {
                        Text(pending).font(.callout.weight(.semibold)).textSelection(.enabled)
                    }
                    if pending != nil {
                        ProgressView("Buscando en la transcripción…").controlSize(.small)
                    }
                    Color.clear.frame(height: 1).id("assistantEnd")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: pending) { proxy.scrollTo("assistantEnd", anchor: .bottom) }
            .onChange(of: turns.last?.id) { proxy.scrollTo("assistantEnd", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let unavailable {
                HStack {
                    Label(model.ui(unavailable), systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Volver a comprobar") { self.unavailable = TranscriptAssistant.availability() }
                        .controlSize(.small)
                }
            } else if paused {
                Text(model.ui(model.active ? "Termina la captura o importación para preguntar." :
                    "El asistente se pausa mientras hay presión de memoria."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let problem {
                Label(model.ui(problem), systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Escribe una pregunta", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(model.selectedSession == nil || pending != nil)
                    .accessibilityIdentifier("assistantQuestion")
                    .onChange(of: question) {
                        if question.count > 500 { question = String(question.prefix(500)) }
                    }
                if pending != nil {
                    Button("Cancelar") { cancel(restore: true) }
                } else {
                    Button("Preguntar", action: ask)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAsk)
                        .accessibilityIdentifier("assistantAsk")
                }
            }
        }
        .padding(12)
    }

    private func ask() {
        guard canAsk, let session = model.selectedSession, let store = model.store else { return }
        let input = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = turns.last(where: { !$0.reply.evidence.isEmpty })
        let token = UUID()
        request = token
        problem = nil
        pending = input
        question = ""
        job = Task {
            do {
                let reply = try await TranscriptAssistant.ask(input, in: session, store: store,
                    previousQuestion: previous?.question, previousEvidence: previous?.reply.evidence ?? [])
                guard !Task.isCancelled, request == token, model.selected == session.id else { return }
                turns.append(Turn(question: input, reply: reply))
                if turns.count > 12 { turns.removeFirst() }
                pending = nil
                job = nil
            } catch {
                guard !Task.isCancelled, request == token, model.selected == session.id else { return }
                pending = nil
                job = nil
                question = input
                problem = (error as? LAIError)?.localizedDescription ??
                    "El modelo local no pudo responder. Intenta reformular la pregunta."
            }
        }
    }

    private func cancel(restore: Bool) {
        guard let pending else { return }
        request = UUID()
        job?.cancel()
        job = nil
        if restore { question = pending }
        self.pending = nil
    }
}
