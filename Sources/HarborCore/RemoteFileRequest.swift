import Foundation

public enum RemoteFileRequest {
    public actor Activity {
        private var lastProgress = ContinuousClock.now
        public init() { }
        public func recordProgress() { lastProgress = .now }
        fileprivate func remaining(_ timeout: TimeInterval) -> Duration {
            ContinuousClock.now.duration(to: lastProgress.advanced(by: .seconds(max(0.01, timeout))))
        }
    }

    public static func perform<T: Sendable>(
        timeout: TimeInterval = 30, activity: Activity = Activity(),
        factory: @Sendable () async throws -> any RemoteFileSession,
        action: @escaping @Sendable (any RemoteFileSession) async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let session = try await factory()
        await activity.recordProgress()
        do {
            let result = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: T.self) { group in
                    group.addTask { try await action(session) }
                    group.addTask {
                        while true {
                            let remaining = await activity.remaining(timeout)
                            guard remaining > .zero else {
                                await session.close()
                                throw FinderReadError.timedOut
                            }
                            try await Task.sleep(for: remaining)
                        }
                    }
                    defer { group.cancelAll() }
                    guard let value = try await group.next() else { throw CancellationError() }
                    return value
                }
            } onCancel: { Task { await session.close() } }
            await session.close()
            try Task.checkCancellation()
            return result
        } catch {
            await session.close()
            if Task.isCancelled { throw CancellationError() }
            if await activity.remaining(timeout) <= .zero { throw FinderReadError.timedOut }
            throw error
        }
    }
}
