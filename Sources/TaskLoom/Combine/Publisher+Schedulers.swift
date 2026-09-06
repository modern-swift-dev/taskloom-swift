#if canImport(Combine)
    import Combine
    import Foundation

    public extension Publisher {

        /// short-hand method to receiving on main thread
        func receiveOnMain() -> Publishers.ReceiveOn<Self, DispatchQueue> {
            receive(on: DispatchQueue.main)
        }

        /// short-hand method to receiving on background dispatch queue
        func receiveOnBackground() -> Publishers.ReceiveOn<Self, DispatchQueue> {
            receive(on: DispatchQueue.background)
        }

        /// short-hand method to receiving on low-priority dispatch queue
        func receiveOnLow() -> Publishers.ReceiveOn<Self, DispatchQueue> {
            receive(on: DispatchQueue.low)
        }

        /// short-hand method to receiving on normal-priority dispatch queue
        func receiveOnNormal() -> Publishers.ReceiveOn<Self, DispatchQueue> {
            receive(on: DispatchQueue.normal)
        }

        /// short-hand method to receiving on high-priority dispatch queue
        func receiveOnHigh() -> Publishers.ReceiveOn<Self, DispatchQueue> {
            receive(on: DispatchQueue.high)
        }

        /// short-hand method to processing on main thread
        func subscribeOnMain() -> Publishers.SubscribeOn<Self, DispatchQueue> {
            subscribe(on: DispatchQueue.main)
        }

        /// short-hand method to processing on background-priority dispatch queue
        func subscribeOnBackground() -> Publishers.SubscribeOn<Self, DispatchQueue> {
            subscribe(on: DispatchQueue.background)
        }

        /// short-hand method to processing on low-priority dispatch queue
        func subscribeOnLow() -> Publishers.SubscribeOn<Self, DispatchQueue> {
            subscribe(on: DispatchQueue.low)
        }

        /// short-hand method to processing on normal-priority dispatch queue
        func subscribeOnNormal() -> Publishers.SubscribeOn<Self, DispatchQueue> {
            subscribe(on: DispatchQueue.normal)
        }

        /// short-hand method to processing on high-priority dispatch queue
        func subscribeOnHigh() -> Publishers.SubscribeOn<Self, DispatchQueue> {
            subscribe(on: DispatchQueue.high)
        }
    }

#endif
