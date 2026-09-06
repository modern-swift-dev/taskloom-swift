#if canImport(Dispatch)
import Dispatch
import Foundation

public extension DispatchQueue {
    /// For background tasks
    static let background = DispatchQueue.global(qos: .background)

    /// For Low-Priority Task
    static let low = DispatchQueue.global(qos: .utility)

    /// For High Priority Task
    static let high = DispatchQueue.global(qos: .userInitiated)

    /// For Highest Priority Task
    static let animation = DispatchQueue.global(qos: .userInteractive)

    /// For Regular Task
    static let normal = DispatchQueue.global(qos: .default)
}

#endif
