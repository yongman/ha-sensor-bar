import Foundation

/// Waits for the menu bar anchor to become visible without blocking AppKit's run loop.
@MainActor
final class PopoverPresenter {
    private var task: Task<Void, Never>?

    func show(attempts: Int = 20, retryDelay: UInt64 = 100_000_000,
              attempt: @escaping @MainActor () -> Bool) {
        cancel()
        task = Task {
            for _ in 0..<attempts {
                guard !Task.isCancelled else { return }
                if attempt() { return }
                do { try await Task.sleep(nanoseconds: retryDelay) }
                catch { return }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
