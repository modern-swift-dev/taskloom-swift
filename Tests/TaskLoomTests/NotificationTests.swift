#if canImport(Combine)
    import Combine
    import Foundation
    import Synchronization
    @testable import TaskLoom
    import Testing

    @Suite(.serialized) struct NotificationTests {
        @Test func publisherFiltersObjectAndReceivesPostedNotification() {
            let name = Notification.Name(UUID().uuidString)
            let expectedObject = NSObject()
            let otherObject = NSObject()
            let count = Mutex(0)
            let subscription = name.publisher(object: expectedObject).sink { _ in
                count.withLock { $0 += 1 }
            }

            name.post(object: otherObject)
            #expect(count.withLock { $0 } == 0)
            name.post(object: expectedObject)
            #expect(count.withLock { $0 } == 1)
            withExtendedLifetime(subscription) {}
        }

        @Test func postPreservesUserInfo() {
            let name = Notification.Name(UUID().uuidString)
            let value = Mutex<String?>(nil)
            let subscription = name.publisher().sink { notification in
                value.withLock { $0 = notification.userInfo?["message"] as? String }
            }

            name.post(userInfo: ["message": "hello"])
            #expect(value.withLock { $0 } == "hello")
            withExtendedLifetime(subscription) {}
        }
    }
#endif
