import Foundation
@testable import TaskLoom
import Testing

struct OperationTracingTests {
    @Test func nestedTracesCorrelateAndPreserveValues() async throws {
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let value = try await withOperationTrace(name: "Parent", recorder: recorder) {
            try await withOperationTrace(name: "Child", file: "Example.swift", function: "load", line: 42) {
                await recordOperationTraceEvent(.retrying(attempt: 2, delay: .seconds(1)))
                return 7
            }
        }
        #expect(value == 7)
        let events = await recorder.events()
        #expect(events.map(\.kind) == [.started, .started, .retrying(attempt: 2, delay: .seconds(1)), .succeeded, .succeeded])
        #expect(events[1].parentID == events[0].id)
        #expect(events[1].id != events[0].id)
        #expect(events[1].source.file == "Example.swift")
        #expect(events[1].source.function == "load")
        #expect(events[1].source.line == 42)
        #expect(events.allSatisfy { $0.elapsed >= .zero })
        #expect(await recorder.activeOperations().isEmpty)
    }

    @Test func cancellationRemainsActiveUntilCooperativeCompletion() async throws {
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let release = TestSignal()
        let task = Task {
            try await withOperationTrace(name: "Ignores cancellation", recorder: recorder) {
                await release.wait()
                return 1
            }
        }
        _ = try await recorder.waitForEvent { $0.kind == .started }
        task.cancel()
        _ = try await recorder.waitForEvent { $0.kind == .cancellationRequested }
        let active = await recorder.activeOperations()
        #expect(active.count == 1)
        #expect(active.first?.cancellationRequested == true)
        await release.signal()
        #expect(try await task.value == 1)
        #expect(await recorder.events().map(\.kind) == [.started, .cancellationRequested, .succeeded])
        #expect(await recorder.activeOperations().isEmpty)
    }

    @Test func failureIsRethrownAndValuesAreNotRecorded() async {
        enum Failure: Error { case expected }
        let recorder = OperationTraceRecorder(recordsEvents: true)
        do {
            try await withOperationTrace(name: "Failure", recorder: recorder) {
                throw Failure.expected
            }
            Issue.record("Expected failure")
        } catch {
            #expect(error is Failure)
        }
        #expect(await recorder.events().map(\.kind) == [.started, .failed])
        #expect(await recorder.activeOperations().isEmpty)
    }

    @Test func snapshotsTrackPermitWaitsWithoutRetainingEvents() async throws {
        let recorder = OperationTraceRecorder()
        try await withOperationTrace(name: "Limited", recorder: recorder) {
            await recordOperationTraceEvent(.waitingForPermit)
            #expect(await recorder.activeOperations().first?.waitingForPermit == true)
            await recordOperationTraceEvent(.acquiredPermit)
            #expect(await recorder.activeOperations().first?.waitingForPermit == false)
        }
        #expect(await recorder.events().isEmpty)
    }

    @Test func cancelledMilestoneWaitDoesNotHang() async {
        let recorder = OperationTraceRecorder()
        let task = Task {
            try await recorder.waitForEvent { $0.kind == .succeeded }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func repeatedExecutionsGetUniqueIDs() async throws {
        let recorder = OperationTraceRecorder(recordsEvents: true)
        for _ in 0..<2 {
            _ = try await withOperationTrace(name: "Repeated", recorder: recorder) { 0 }
        }
        let starts = await recorder.events().filter { $0.kind == .started }
        #expect(starts.count == 2)
        #expect(starts[0].id != starts[1].id)
    }

    @Test func overlappingChildPermitWaitsRemainVisible() async throws {
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let semaphore = AsyncSemaphore(limit: 1)
        let entered = TestSignal()
        let release = TestSignal()
        try await semaphore.wait()
        try await withOperationTrace(name: "Parallel permits", recorder: recorder) {
            let first = Task {
                try await semaphore.withPermit {
                    await entered.signal()
                    await release.wait()
                }
            }
            while await semaphore.waitingCount < 1 { await Task.yield() }
            let second = Task { try await semaphore.withPermit {} }
            while await semaphore.waitingCount < 2 { await Task.yield() }
            await semaphore.signal()
            await entered.wait()
            #expect(await recorder.activeOperations().first?.waitingForPermit == true)
            await release.signal()
            try await first.value
            try await second.value
            #expect(await recorder.activeOperations().first?.waitingForPermit == false)
        }
        #expect(await semaphore.availablePermits == 1)
    }

    @Test func recoveredChildWaitCancellationClearsSnapshot() async throws {
        let recorder = OperationTraceRecorder(recordsEvents: true)
        let semaphore = AsyncSemaphore(limit: 1)
        try await semaphore.wait()
        try await withOperationTrace(name: "Recovers child cancellation", recorder: recorder) {
            let child = Task { try await semaphore.withPermit {} }
            while await semaphore.waitingCount < 1 { await Task.yield() }
            child.cancel()
            do {
                try await child.value
                Issue.record("Expected cancellation")
            } catch {
                #expect(error is CancellationError)
            }
            #expect(await recorder.activeOperations().first?.waitingForPermit == false)
            #expect(await recorder.activeOperations().first?.cancellationRequested == false)
        }
        await semaphore.signal()
        #expect(await semaphore.availablePermits == 1)
        #expect(await recorder.events().map(\.kind) == [.started, .waitingForPermit, .permitWaitCancelled, .succeeded])
    }

}
