import Foundation

actor FinderOperationGate {
    private var held = false
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []

    func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if held {
                    waiting.append((id, continuation))
                } else {
                    held = true
                    continuation.resume(returning: ())
                }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    func release() {
        if waiting.isEmpty { held = false } else { waiting.removeFirst().1.resume(returning: ()) }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
}
