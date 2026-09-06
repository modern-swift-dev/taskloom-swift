#if canImport(Dispatch)
    import Dispatch
    import Foundation
    @testable import TaskLoom
    import Testing

    @Suite(.serialized) struct DispatchQueueExtTests {

        // MARK: - Queue Identity Tests

        @Test func backgroundQueueIsGlobalBackground() {
            #if os(Linux)
                #expect(!DispatchQueue.background.label.isEmpty)
            #else
                #expect(DispatchQueue.background === DispatchQueue.global(qos: .background))
            #endif
        }

        @Test func lowQueueIsGlobalUtility() {
            #if os(Linux)
                #expect(!DispatchQueue.low.label.isEmpty)
            #else
                #expect(DispatchQueue.low === DispatchQueue.global(qos: .utility))
            #endif
        }

        @Test func highQueueIsGlobalUserInitiated() {
            #if os(Linux)
                #expect(!DispatchQueue.high.label.isEmpty)
            #else
                #expect(DispatchQueue.high === DispatchQueue.global(qos: .userInitiated))
            #endif
        }

        @Test func animationQueueIsGlobalUserInteractive() {
            #if os(Linux)
                #expect(!DispatchQueue.animation.label.isEmpty)
            #else
                #expect(DispatchQueue.animation === DispatchQueue.global(qos: .userInteractive))
            #endif
        }

        @Test func normalQueueIsGlobalDefault() {
            #if os(Linux)
                #expect(!DispatchQueue.normal.label.isEmpty)
            #else
                #expect(DispatchQueue.normal === DispatchQueue.global(qos: .default))
            #endif
        }

        // MARK: - Convenience Naming

        @Test func queueNamingConvenience() {
            #if os(Linux)
                #expect(!DispatchQueue.background.label.isEmpty)
                #expect(!DispatchQueue.low.label.isEmpty)
                #expect(!DispatchQueue.high.label.isEmpty)
                #expect(!DispatchQueue.animation.label.isEmpty)
                #expect(!DispatchQueue.normal.label.isEmpty)
            #else
                // Verify all convenience properties return proper global queues
                #expect(DispatchQueue.background.label == "com.apple.root.background-qos")
                #expect(DispatchQueue.low.label == "com.apple.root.utility-qos")
                #expect(DispatchQueue.high.label == "com.apple.root.user-initiated-qos")
                #expect(DispatchQueue.animation.label == "com.apple.root.user-interactive-qos")
                #expect(DispatchQueue.normal.label == "com.apple.root.default-qos")
            #endif
        }
    }
#endif
