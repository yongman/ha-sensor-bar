import Foundation

/// A single cancellable loop awaits each refresh before scheduling the next.
@MainActor
public final class RefreshScheduler {
    private var task: Task<Void, Never>?
    public init() {}
    deinit { task?.cancel() }

    public func start(interval: TimeInterval, operation: @escaping @MainActor () async -> Void) {
        stop()
        let delay = UInt64(min(3600, max(15, interval)) * 1_000_000_000)
        task = Task {
            while !Task.isCancelled {
                await operation()
                do { try await Task.sleep(nanoseconds: delay) }
                catch { return }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
