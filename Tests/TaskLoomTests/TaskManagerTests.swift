import Foundation
@testable import TaskLoom
import Testing

@Suite(.serialized) struct TaskManagerTests {

    // MARK: - TaskHandle Tests

    @Test func taskHandleInitialization() {
        let handle = TaskManager.TaskHandle(
            file: "/path/to/MyFile.swift",
            functionName: "testFunction",
            line: 42
        )

        #expect(handle.file == "MyFile.swift")
        #expect(handle.functionName == "testFunction")
        #expect(handle.line == 42)
    }

    @Test func taskHandleExtractsFilenameFromPath() {
        let handle = TaskManager.TaskHandle(
            file: "/Users/dev/project/Sources/Module/File.swift",
            functionName: "test",
            line: 1
        )

        #expect(handle.file == "File.swift")
    }

    @Test func taskHandleEquality() {
        let id = UUID()
        let handle1 = TaskManager.TaskHandle(id: id, file: "File.swift", functionName: "test", line: 1)
        let handle2 = TaskManager.TaskHandle(id: id, file: "Other.swift", functionName: "other", line: 99)

        #expect(handle1 == handle2)
    }

    @Test func taskHandleInequalityWithDifferentIds() {
        let handle1 = TaskManager.TaskHandle(file: "File.swift", functionName: "test", line: 1)
        let handle2 = TaskManager.TaskHandle(file: "File.swift", functionName: "test", line: 1)

        #expect(handle1 != handle2)
    }

    @Test func taskHandleHashUsesId() {
        let id = UUID()
        let handle1 = TaskManager.TaskHandle(id: id, file: "File.swift", functionName: "test", line: 1)
        let handle2 = TaskManager.TaskHandle(id: id, file: "Other.swift", functionName: "other", line: 99)

        #expect(handle1.hashValue == handle2.hashValue)
    }

    @Test func taskHandleDescription() {
        let handle = TaskManager.TaskHandle(file: "MyFile.swift", functionName: "myFunction", line: 123)

        #expect(handle.description == "MyFile.swift#myFunction::123")
        #expect(handle.debugDescription == "MyFile.swift#myFunction::123")
    }

    @Test func taskHandleEncoding() throws {
        let handle = TaskManager.TaskHandle(file: "Test.swift", functionName: "test", line: 1)

        let encoder = JSONEncoder()
        let data = try encoder.encode(handle)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["file"] as? String == "Test.swift")
        #expect(json?["functionName"] as? String == "test")
        #expect(json?["line"] as? Int == 1)
        #expect(json?["id"] != nil)
        #expect(json?["created"] != nil)
        let duration = try #require(json?["duration"] as? Double)
        #expect(duration >= 0)

        let laterData = try encoder.encode(handle)
        let laterJSON = try JSONSerialization.jsonObject(with: laterData) as? [String: Any]
        let laterDuration = try #require(laterJSON?["duration"] as? Double)
        #expect(laterDuration >= duration)
    }

    // MARK: - TaskManager State Tests

    @Test func initialState() {
        let manager = TaskManager()
        let state = manager.getState()

        #expect(state.nbPendingTaskCount == 0)
        #expect(state.nbPendingTaskMax == 0)
        #expect(state.nbCreatedTaskTotal == 0)
        #expect(state.nbAliveTaskCount == 0)
        #expect(state.nbAliveTaskMax == 0)
        #expect(state.nbCompletedTaskCount == 0)
        #expect(state.nbCancelledTaskCount == 0)
    }

    @Test func onTaskCreatedIncrementsCounters() {
        let manager = TaskManager()

        _ = manager.onTaskCreated("File.swift", "test", 1)
        let state = manager.getState()

        #expect(state.nbPendingTaskCount == 1)
        #expect(state.nbPendingTaskMax == 1)
        #expect(state.nbCreatedTaskTotal == 1)
    }

    @Test func onTaskCreatedTracksMaximum() {
        let manager = TaskManager()

        let handle1 = manager.onTaskCreated("File.swift", "test", 1)
        _ = manager.onTaskCreated("File.swift", "test", 2)
        _ = manager.onTaskCreated("File.swift", "test", 3)

        var state = manager.getState()
        #expect(state.nbPendingTaskMax == 3)

        manager.onTaskStarted(handle: handle1)
        manager.onTaskCompleted(handle: handle1, cancelled: false)

        state = manager.getState()
        #expect(state.nbPendingTaskMax == 3)
        #expect(state.nbPendingTaskCount == 2)
    }

    @Test func onTaskStartedIncrementsAliveCount() {
        let manager = TaskManager()

        let handle = manager.onTaskCreated("File.swift", "test", 1)
        manager.onTaskStarted(handle: handle)

        let state = manager.getState()
        #expect(state.nbAliveTaskCount == 1)
        #expect(state.nbAliveTaskMax == 1)
    }

    @Test func onTaskCompletedDecrementsCounters() {
        let manager = TaskManager()

        let handle = manager.onTaskCreated("File.swift", "test", 1)
        manager.onTaskStarted(handle: handle)
        manager.onTaskCompleted(handle: handle, cancelled: false)

        let state = manager.getState()
        #expect(state.nbAliveTaskCount == 0)
        #expect(state.nbPendingTaskCount == 0)
        #expect(state.nbCompletedTaskCount == 1)
        #expect(state.nbCancelledTaskCount == 0)
    }

    @Test func onTaskCompletedTracksCancellation() {
        let manager = TaskManager()

        let handle = manager.onTaskCreated("File.swift", "test", 1)
        manager.onTaskStarted(handle: handle)
        manager.onTaskCompleted(handle: handle, cancelled: true)

        let state = manager.getState()
        #expect(state.nbCompletedTaskCount == 1)
        #expect(state.nbCancelledTaskCount == 1)
    }

    @Test func fullTaskLifecycle() {
        let manager = TaskManager()

        let handle1 = manager.onTaskCreated("File.swift", "task1", 1)
        let handle2 = manager.onTaskCreated("File.swift", "task2", 2)
        let handle3 = manager.onTaskCreated("File.swift", "task3", 3)

        var state = manager.getState()
        #expect(state.nbPendingTaskCount == 3)
        #expect(state.nbCreatedTaskTotal == 3)

        manager.onTaskStarted(handle: handle1)
        manager.onTaskStarted(handle: handle2)

        state = manager.getState()
        #expect(state.nbAliveTaskCount == 2)
        #expect(state.nbAliveTaskMax == 2)

        manager.onTaskCompleted(handle: handle1, cancelled: false)

        state = manager.getState()
        #expect(state.nbAliveTaskCount == 1)
        #expect(state.nbPendingTaskCount == 2)
        #expect(state.nbCompletedTaskCount == 1)

        manager.onTaskStarted(handle: handle3)

        state = manager.getState()
        #expect(state.nbAliveTaskCount == 2)
        #expect(state.nbAliveTaskMax == 2)

        manager.onTaskCompleted(handle: handle2, cancelled: true)
        manager.onTaskCompleted(handle: handle3, cancelled: false)

        state = manager.getState()
        #expect(state.nbAliveTaskCount == 0)
        #expect(state.nbPendingTaskCount == 0)
        #expect(state.nbCompletedTaskCount == 3)
        #expect(state.nbCancelledTaskCount == 1)
    }

    @Test func completingNonStartedTaskDoesNotUnderflow() {
        let manager = TaskManager()

        let handle = manager.onTaskCreated("File.swift", "test", 1)
        manager.onTaskCompleted(handle: handle, cancelled: false)

        let state = manager.getState()
        #expect(state.nbAliveTaskCount == 0)
    }
}
