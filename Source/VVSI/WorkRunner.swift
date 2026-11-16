import Foundation

/// Shared execution and lifetime management for both observation adapters.
@MainActor
final class WorkRunner<S: StateProtocol> {
    @MainActor
    private final class Snapshot {
        var value: S
        init(_ value: S) { self.value = value }
    }

    private struct RunningWork: Sendable {
        /// `.cancelPrevious` and `.dropWhileRunning` share one slot.
        /// `.concurrent` does not occupy it and is not replaced by it.
        let takesSlot: Bool
        let control: WorkControl
    }

    /// Receives whether the slot is busy after every change. The owner stores it
    /// as an observable property.
    var onSlotChange: ((Bool) -> Void)?

    private let snapshot: Snapshot
    private var nextID: UInt64 = 0
    private var running: [UInt64: RunningWork] = [:]

    init(_ state: S) {
        snapshot = Snapshot(state)
    }

    deinit {
        for work in running.values { work.control.resolve(.cancelled) }
    }

    var activeWorkCount: Int {
        running.values.filter { $0.control.isActive }.count
    }

    func record(_ state: S) {
        snapshot.value = state
    }

    func start(_ work: Work<S>, updater: @escaping StateUpdater<S>) -> WorkHandle {
        // A handle may have been cancelled while its operation is still running.
        running = running.filter { $0.value.control.isActive }

        switch work.policy {
        case .cancelPrevious:
            cancelSlot()
        case .dropWhileRunning:
            if running.values.contains(where: \.takesSlot) {
                let control = WorkControl()
                control.resolve(.dropped)
                return WorkHandle(control: control)
            }
        case .concurrent:
            break
        }

        let takesSlot = work.policy != .concurrent
        let control = WorkControl(onCancel: takesSlot ? slotCancelled() : nil)
        let id = nextID
        nextID &+= 1
        let task = Task { @MainActor [weak self, snapshot] in
            defer {
                if let self {
                    self.running[id] = nil
                    self.publishSlot()
                }
                control.resolve(.completed)
            }
            guard control.isActive, !Task.isCancelled else { return }

            // The task retains the last state snapshot and a weak owner updater,
            // never the runner or the observation adapter across this await.
            await work.operation(
                { snapshot.value },
                { update in
                    guard control.isActive, !Task.isCancelled else { return }
                    updater(update)
                }
            )
        }
        running[id] = RunningWork(takesSlot: takesSlot, control: control)
        control.attach(task)
        publishSlot()
        return WorkHandle(control: control)
    }

    func cancel() {
        let work = running.values
        running.removeAll()
        for item in work { item.control.resolve(.cancelled) }
        publishSlot()
    }

    private func cancelSlot() {
        let ids = running.compactMap { $0.value.takesSlot ? $0.key : nil }
        for id in ids {
            running.removeValue(forKey: id)?.control.resolve(.cancelled)
        }
    }

    private func publishSlot() {
        onSlotChange?(running.values.contains { $0.takesSlot && $0.control.isActive })
    }

    /// A cancelled operation may ignore cancellation and keep running, so the
    /// slot is released when its handle is cancelled, not when its task exits.
    /// Handles can be cancelled from any thread.
    private func slotCancelled() -> @Sendable () -> Void {
        { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.publishSlot() }
            } else {
                Task { @MainActor in self?.publishSlot() }
            }
        }
    }
}
