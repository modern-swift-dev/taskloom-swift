public extension Collection where Element: Sendable {
    /// Transforms elements concurrently while preserving their input order.
    ///
    /// At most `maxConcurrency` child tasks run at once. A failure cancels the
    /// remaining children, and cancellation stops scheduling additional elements.
    /// As with all task groups, this method waits for children to finish; transforms
    /// must cooperate with cancellation to stop promptly.
    ///
    /// - Precondition: `maxConcurrency` is greater than zero.
    func concurrentMap<Output: Sendable>(
        maxConcurrency: Int,
        _ transform: @escaping @Sendable (Element) async throws -> Output
    ) async throws -> [Output] {
        precondition(maxConcurrency > 0, "maxConcurrency must be greater than zero")
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var iterator = enumerated().makeIterator()
            var results = [Output?](repeating: nil, count: count)

            func schedule(_ item: (offset: Int, element: Element)) throws {
                try Task.checkCancellation()
                group.addTask {
                    try Task.checkCancellation()
                    return (item.offset, try await transform(item.element))
                }
            }

            for _ in 0 ..< Swift.min(maxConcurrency, count) {
                if let item = iterator.next() {
                    try schedule(item)
                }
            }

            while let (index, output) = try await group.next() {
                try Task.checkCancellation()
                results[index] = .some(output)
                if let item = iterator.next() {
                    try schedule(item)
                }
            }
            try Task.checkCancellation()
            // Every scheduled element has completed successfully at this point.
            return results.map { result in
                guard let result else {
                    preconditionFailure("Every scheduled element must have a result")
                }
                return result
            }
        }
    }

    /// Runs `body` for every element concurrently.
    ///
    /// At most `maxConcurrency` child tasks run at once. A failure cancels the
    /// remaining children and is rethrown, and cancellation stops scheduling additional elements.
    /// As with all task groups, this method waits for children to finish; bodies
    /// must cooperate with cancellation to stop promptly.
    ///
    /// - Precondition: `maxConcurrency` is greater than zero.
    func concurrentForEach(
        maxConcurrency: Int,
        _ body: @escaping @Sendable (Element) async throws -> Void
    ) async throws {
        precondition(maxConcurrency > 0, "maxConcurrency must be greater than zero")
        try Task.checkCancellation()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = makeIterator()

            func schedule(_ element: Element) throws {
                try Task.checkCancellation()
                group.addTask {
                    try Task.checkCancellation()
                    try await body(element)
                }
            }

            for _ in 0 ..< maxConcurrency {
                guard let element = iterator.next() else {
                    break
                }
                try schedule(element)
            }

            while try await group.next() != nil {
                try Task.checkCancellation()
                if let element = iterator.next() {
                    try schedule(element)
                }
            }
            try Task.checkCancellation()
        }
    }
}
