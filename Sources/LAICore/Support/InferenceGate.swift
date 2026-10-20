import Foundation
// One heavyweight inference at a time. Audio IO is never admitted here.
public actor InferenceGate {
    public static let shared=InferenceGate()
    private var busy=false
    private struct Waiter { let id:UUID; let continuation:CheckedContinuation<Void,any Error> }
    private var waiters:[Waiter]=[]
    public func perform<T:Sendable>(_ operation:@Sendable () async throws -> T) async throws -> T {
        let id=UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if busy {
                guard waiters.count<8 else { throw LAIError.message("La cola de inferencia local está ocupada. Reintenta después.") }
                try await withCheckedThrowingContinuation { waiters.append(Waiter(id:id,continuation:$0)) }
            } else { busy=true }
        } onCancel: { Task { await self.cancel(id) } }
        do { try Task.checkCancellation(); let value=try await operation(); release(); return value }
        catch { release(); throw error }
    }
    private func cancel(_ id:UUID) {
        guard let index=waiters.firstIndex(where:{$0.id==id}) else { return }
        waiters.remove(at:index).continuation.resume(throwing:CancellationError())
    }
    private func release() { if waiters.isEmpty { busy=false } else { waiters.removeFirst().continuation.resume() } }
}
