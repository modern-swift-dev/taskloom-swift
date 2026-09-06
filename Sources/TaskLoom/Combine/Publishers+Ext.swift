#if canImport(Combine)
import Combine
import Foundation

/// Extension for publishers, hadding easier integration
public extension Publishers {

    /// Return a timer publisher
    static func timer(_ interval: TimeInterval, runLoop: RunLoop = RunLoop.current, mode: RunLoop.Mode = .default) -> Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: interval, on: runLoop, in: mode).autoconnect()
    }
}

#endif
