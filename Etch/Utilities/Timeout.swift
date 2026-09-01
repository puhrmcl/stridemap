import Foundation

/// Runs `operation`, returning its result — or `fallback` if it doesn't finish within
/// `seconds`.
///
/// Unlike `withTaskGroup`, this does **not** wait for a timed-out operation to finish before
/// returning. That matters for non-cancellable work like HealthKit's continuation-based
/// queries: a task group would block on the stuck child forever (defeating the timeout),
/// whereas here the slow operation is simply abandoned once the deadline passes.
func withTimeout<T: Sendable>(
    _ seconds: Double,
    fallback: T,
    operation: @escaping @Sendable () async -> T
) async -> T {
    let gate = ResumeGate<T>()
    return await withCheckedContinuation { continuation in
        gate.attach(continuation)
        let work = Task { gate.resume(with: await operation()) }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
            gate.resume(with: fallback)
        }
    }
}

/// Holds the continuation and guarantees it is resumed exactly once — whether the work
/// finishes or the timeout fires first. The continuation lives inside the gate (which is
/// `Sendable`) so the racing tasks never capture the non-Sendable continuation directly.
private final class ResumeGate<T>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private var resumed = false
    private let lock = NSLock()

    func attach(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(with value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation?.resume(returning: value)
        continuation = nil
    }
}
