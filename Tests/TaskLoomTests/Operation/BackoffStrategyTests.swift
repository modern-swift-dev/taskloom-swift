import Foundation
@testable import TaskLoom
import Testing

@Suite(.serialized) struct BackoffStrategyTests {

    // MARK: - None

    @Test func noneReturnsZeroDelay() {
        let strategy = BackoffStrategy.none

        #expect(strategy.delay(for: 0) == .zero)
        #expect(strategy.delay(for: 1) == .zero)
        #expect(strategy.delay(for: 10) == .zero)
    }

    // MARK: - Constant

    @Test func constantReturnsSameDelay() {
        let strategy = BackoffStrategy.constant(.milliseconds(100))

        #expect(strategy.delay(for: 0) == .milliseconds(100))
        #expect(strategy.delay(for: 1) == .milliseconds(100))
        #expect(strategy.delay(for: 5) == .milliseconds(100))
    }

    // MARK: - Linear

    @Test func linearIncreasesLinearly() {
        let strategy = BackoffStrategy.linear(base: .milliseconds(100))

        // delay = base * (attempt + 1)
        #expect(strategy.delay(for: 0) == .milliseconds(100)) // 100 * 1
        #expect(strategy.delay(for: 1) == .milliseconds(200)) // 100 * 2
        #expect(strategy.delay(for: 2) == .milliseconds(300)) // 100 * 3
        #expect(strategy.delay(for: 4) == .milliseconds(500)) // 100 * 5
    }

    // MARK: - Exponential

    @Test func exponentialIncreasesExponentially() {
        let strategy = BackoffStrategy.exponential(base: .milliseconds(100), max: nil)

        // delay = base * 2^attempt
        #expect(strategy.delay(for: 0) == .milliseconds(100)) // 100 * 1
        #expect(strategy.delay(for: 1) == .milliseconds(200)) // 100 * 2
        #expect(strategy.delay(for: 2) == .milliseconds(400)) // 100 * 4
        #expect(strategy.delay(for: 3) == .milliseconds(800)) // 100 * 8
        #expect(strategy.delay(for: 4) == .milliseconds(1600)) // 100 * 16
    }

    @Test func exponentialRespectsMaxCap() {
        let strategy = BackoffStrategy.exponential(base: .milliseconds(100), max: .milliseconds(500))

        #expect(strategy.delay(for: 0) == .milliseconds(100))
        #expect(strategy.delay(for: 1) == .milliseconds(200))
        #expect(strategy.delay(for: 2) == .milliseconds(400))
        #expect(strategy.delay(for: 3) == .milliseconds(500)) // Capped
        #expect(strategy.delay(for: 10) == .milliseconds(500)) // Still capped
    }

    // MARK: - Exponential With Jitter

    @Test func exponentialWithJitterIsWithinBounds() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: .milliseconds(100), max: nil)

        // Run multiple times to test randomness
        for _ in 0 ..< 10 {
            let delay = strategy.delay(for: 2) // Base delay would be 400ms
            // Jitter is 0-100% of the delay, so result should be 0-400ms
            #expect(delay >= .zero)
            #expect(delay <= .milliseconds(400))
        }
    }

    @Test func exponentialWithJitterRespectsMaxCap() {
        let strategy = BackoffStrategy.exponentialWithJitter(base: .milliseconds(100), max: .milliseconds(200))

        for _ in 0 ..< 10 {
            let delay = strategy.delay(for: 5) // Would be 3200ms without cap
            // With cap at 200ms and jitter, result should be 0-200ms
            #expect(delay >= .zero)
            #expect(delay <= .milliseconds(200))
        }
    }

    // MARK: - Custom

    @Test func customUsesProvidedCalculator() {
        let strategy = BackoffStrategy.custom { attempt in
            .milliseconds(Int64(attempt * attempt * 10))
        }

        #expect(strategy.delay(for: 0) == .milliseconds(0)) // 0 * 0 * 10
        #expect(strategy.delay(for: 1) == .milliseconds(10)) // 1 * 1 * 10
        #expect(strategy.delay(for: 2) == .milliseconds(40)) // 2 * 2 * 10
        #expect(strategy.delay(for: 3) == .milliseconds(90)) // 3 * 3 * 10
    }

    // MARK: - Convenience Initializers

    @Test func exponentialDefaultHasReasonableDefaults() {
        let strategy = BackoffStrategy.exponentialDefault()

        #expect(strategy.delay(for: 0) == .milliseconds(100))
        #expect(strategy.delay(for: 1) == .milliseconds(200))
        // At high attempts, should be capped at 30 seconds
        #expect(strategy.delay(for: 20) == .seconds(30))
    }

    @Test func exponentialDefaultAcceptsCustomValues() {
        let strategy = BackoffStrategy.exponentialDefault(base: .milliseconds(50), max: .seconds(1))

        #expect(strategy.delay(for: 0) == .milliseconds(50))
        #expect(strategy.delay(for: 1) == .milliseconds(100))
        #expect(strategy.delay(for: 10) == .seconds(1)) // Capped
    }

    @Test func fixedUsesProvidedDelays() {
        let strategy = BackoffStrategy.fixed([
            .milliseconds(100),
            .milliseconds(200),
            .milliseconds(500)
        ])

        #expect(strategy.delay(for: 0) == .milliseconds(100))
        #expect(strategy.delay(for: 1) == .milliseconds(200))
        #expect(strategy.delay(for: 2) == .milliseconds(500))
        // Beyond array length, uses last value
        #expect(strategy.delay(for: 3) == .milliseconds(500))
        #expect(strategy.delay(for: 10) == .milliseconds(500))
    }

    @Test func fixedWithEmptyArrayReturnsNone() {
        let strategy = BackoffStrategy.fixed([])

        #expect(strategy.delay(for: 0) == .zero)
        #expect(strategy.delay(for: 5) == .zero)
    }
}
