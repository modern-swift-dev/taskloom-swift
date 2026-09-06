/// A simple one-shot signal for coordinating between two tasks.
actor TestSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() {}

    /// Signals that the task is ready.
    func signal() {
        isSignaled = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    /// Waits until signal() is called.
    func wait() async {
        if isSignaled {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
