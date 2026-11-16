import Foundation

/// The terminal state of a Work's lifetime, not its application-specific result.
public enum WorkOutcome: Sendable, Equatable {
    case completed
    case cancelled
    case dropped
}

/// Controls and awaits a single Work without retaining its ViewState.
public struct WorkHandle: Sendable {
    let control: WorkControl

    /// Invalidates updates and requests cooperative cancellation immediately.
    public func cancel() {
        control.cancel()
    }

    /// Waits for completion, cancellation, or rejection by a work policy.
    /// Cancelling the waiting task also cancels this Work. Cancellation returns
    /// promptly even if the operation ignores cancellation and is still running.
    @discardableResult
    public func finish() async -> WorkOutcome {
        await withTaskCancellationHandler {
            await control.wait()
        } onCancel: {
            cancel()
        }
    }
}

// Every mutable field is protected by lock. Cancellation handlers and owner
// deinitialization may run off MainActor; task cancellation and continuation
// resumption must happen outside the lock to allow reentrant cancellation.
final class WorkControl: @unchecked Sendable {
    private let lock = NSLock()
    private let onCancel: (@Sendable () -> Void)?
    private var outcome: WorkOutcome?
    private var task: Task<Void, Never>?
    private var waiters: [CheckedContinuation<WorkOutcome, Never>] = []

    /// `onCancel` runs only for cancellation through a handle, which the runner
    /// cannot observe on its own; runner-initiated resolutions skip it.
    init(onCancel: (@Sendable () -> Void)? = nil) {
        self.onCancel = onCancel
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return outcome == nil
    }

    func attach(_ task: Task<Void, Never>) {
        lock.lock()
        let ended = outcome != nil
        if !ended { self.task = task }
        lock.unlock()
        if ended { task.cancel() }
    }

    func cancel() {
        if resolve(.cancelled) { onCancel?() }
    }

    @discardableResult
    func resolve(_ result: WorkOutcome) -> Bool {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return false
        }
        outcome = result
        let task = self.task
        self.task = nil
        let waiters = self.waiters
        self.waiters.removeAll()
        lock.unlock()

        if result == .cancelled { task?.cancel() }
        for waiter in waiters { waiter.resume(returning: result) }
        return true
    }

    func wait() async -> WorkOutcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(returning: outcome)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
