import Foundation
import Logging
import Synchronization

/// A lifecycle event for an explicitly traced operation. Values and error messages are never captured.
public struct OperationTraceEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case started
        /// The one-based number of the next attempt and its preceding delay.
        case retrying(attempt: Int, delay: Duration)
        case waitingForPermit
        case acquiredPermit
        case permitWaitCancelled
        case cancellationRequested
        case succeeded
        case failed
    }

    public struct Source: Sendable, Equatable {
        public let file: String
        public let function: String
        public let line: UInt
    }

    public let id: UUID
    public let parentID: UUID?
    public let name: String
    public let source: Source
    public let kind: Kind
    public let elapsed: Duration
}

/// A currently running, explicitly traced operation, including operations still cooperating with cancellation.
public struct OperationTraceSnapshot: Sendable, Equatable {
    public let id: UUID
    public let parentID: UUID?
    public let name: String
    public let source: OperationTraceEvent.Source
    public let elapsed: Duration
    public let cancellationRequested: Bool
    public let waitingForPermit: Bool
}

/// Records diagnostics for operations that opt into tracing. Event retention is opt-in and unbounded.
/// Keep recording scoped to tests or a bounded debugging session.
public actor OperationTraceRecorder {
    private struct Active {
        let event: OperationTraceEvent
        let start: ContinuousClock.Instant
        var cancellationRequested = false
        var pendingPermitWaits = 0
    }

    private struct Waiter {
        let predicate: @Sendable (OperationTraceEvent) -> Bool
        let continuation: CheckedContinuation<OperationTraceEvent, any Error>
    }

    private let recordsEvents: Bool
    private var history: [OperationTraceEvent] = []
    private var active: [UUID: Active] = [:]
    private var waiters: [UUID: Waiter] = [:]

    public init(recordsEvents: Bool = false) {
        self.recordsEvents = recordsEvents
    }

    public func events() -> [OperationTraceEvent] {
        history
    }

    public func activeOperations() -> [OperationTraceSnapshot] {
        active.values.map {
            OperationTraceSnapshot(
                id: $0.event.id, parentID: $0.event.parentID, name: $0.event.name,
                source: $0.event.source, elapsed: $0.start.duration(to: .now),
                cancellationRequested: $0.cancellationRequested, waitingForPermit: $0.pendingPermitWaits > 0
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Waits for a matching retained or future event. Cancellation removes the waiter.
    /// Enable `recordsEvents` to observe milestones that may already have happened.
    public func waitForEvent(
        matching predicate: @escaping @Sendable (OperationTraceEvent) -> Bool
    ) async throws -> OperationTraceEvent {
        try Task.checkCancellation()
        if let event = history.first(where: predicate) {
            return event
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = Waiter(predicate: predicate, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    fileprivate func record(_ event: OperationTraceEvent, start: ContinuousClock.Instant) {
        if event.kind == .started {
            active[event.id] = Active(event: event, start: start)
        } else {
            // Inherited task-local context may outlive its originating operation.
            guard active[event.id] != nil else {
                return
            }
            switch event.kind {
                case .cancellationRequested: active[event.id]?.cancellationRequested = true
                case .waitingForPermit: active[event.id]?.pendingPermitWaits += 1
                case .acquiredPermit,
                     .permitWaitCancelled:
                    if let count = active[event.id]?.pendingPermitWaits {
                        active[event.id]?.pendingPermitWaits = max(0, count - 1)
                    }
                case .succeeded,
                     .failed: active.removeValue(forKey: event.id)
                default: break
            }
        }
        if recordsEvents {
            history.append(event)
        }
        let matching = waiters.filter { $0.value.predicate(event) }.map(\.key)
        for id in matching {
            waiters.removeValue(forKey: id)?.continuation.resume(returning: event)
        }
        taskLoomLogger.debug("Operation lifecycle", metadata: [
            "operation": .string(event.name), "execution_id": .string(event.id.uuidString),
            "parent_id": .string(event.parentID?.uuidString ?? ""),
            "event": .string(String(describing: event.kind)),
            "elapsed": .string(String(describing: event.elapsed)),
            "file": .string(event.source.file), "function": .string(event.source.function),
            "line": .string(String(event.source.line))
        ])
    }
}

private final class OperationTraceContext: Sendable {
    private struct State: Sendable {
        var finished = false
        var cancellation: Task<Void, Never>?
    }

    private let state = Mutex(State())
    let id = UUID()
    let parentID: UUID?
    let name: String
    let source: OperationTraceEvent.Source
    let recorder: OperationTraceRecorder
    let start = ContinuousClock.now

    init(name: String, source: OperationTraceEvent.Source, recorder: OperationTraceRecorder, parentID: UUID?) {
        self.name = name
        self.source = source
        self.recorder = recorder
        self.parentID = parentID
    }

    func emit(_ kind: OperationTraceEvent.Kind) async {
        await recorder.record(OperationTraceEvent(
            id: id, parentID: parentID, name: name, source: source,
            kind: kind, elapsed: start.duration(to: .now)
        ), start: start)
    }

    func cancel() {
        state.withLock { state in
            guard !state.finished, state.cancellation == nil else {
                return
            }
            state.cancellation = Task { await self.emit(.cancellationRequested) }
        }
    }

    func finish(_ kind: OperationTraceEvent.Kind) async {
        let cancellation = state.withLock { state in
            state.finished = true
            return state.cancellation
        }
        await cancellation?.value
        await emit(kind)
    }
}

private enum OperationTracing {
    @TaskLocal static var context: OperationTraceContext?
}

/// Executes an operation with a unique execution ID and inherited parent correlation.
/// Cancellation requests are reported separately from completion; tracing does not alter the result.
public func withOperationTrace<Success: Sendable>(
    name: String,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    recorder: OperationTraceRecorder? = nil,
    operation: @Sendable () async throws -> Success
) async throws -> Success {
    let parent = OperationTracing.context
    let context = OperationTraceContext(
        name: name, source: .init(file: file, function: function, line: line),
        recorder: recorder ?? parent?.recorder ?? OperationTraceRecorder(), parentID: parent?.id
    )
    await context.emit(.started)
    return try await OperationTracing.$context.withValue(context) {
        try await withTaskCancellationHandler {
            do {
                let result = try await operation()
                await context.finish(.succeeded)
                return result
            } catch {
                await context.finish(.failed)
                throw error
            }
        } onCancel: {
            context.cancel()
        }
    }
}

/// Emits policy diagnostics only when called inside an explicitly traced operation.
func recordOperationTraceEvent(_ kind: OperationTraceEvent.Kind) async {
    await OperationTracing.context?.emit(kind)
}
