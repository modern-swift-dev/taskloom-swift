#if canImport(Combine)
    import Combine
    import Foundation

    /// Add conformance to `Cancellable` to `Task`
    extension Task: @retroactive Cancellable {}

    /// An extension for the swift concurrency task type that erase the origin type
    public extension Task {

        /// Utility to make a task cancellable like a combine `AnyCancellable`
        func eraseToAnyCancellable() -> AnyCancellable {
            .init(self)
        }
    }

    /// Add conformance to `Cancellable` to `TaskGroup`
    extension TaskGroup: @retroactive Cancellable {
        public func cancel() {
            cancelAll()
        }
    }

    /// An extension for the swift concurrency `TaskGroup` type that erase the origin type
    public extension TaskGroup {

        /// Utility to make a task cancellable like a combine `AnyCancellable`
        func eraseToAnyCancellable() -> AnyCancellable {
            .init(self)
        }
    }

    /// Add conformance to `Cancellable` to `ThrowingTaskGroup`
    extension ThrowingTaskGroup: @retroactive Cancellable {
        public func cancel() {
            cancelAll()
        }
    }

    /// An extension for the swift concurrency `ThrowingTaskGroup` type that erase the origin type
    public extension ThrowingTaskGroup {

        /// Utility to make a task cancellable like a combine `AnyCancellable`
        func eraseToAnyCancellable() -> AnyCancellable {
            .init(self)
        }
    }

#endif
