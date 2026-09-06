#if canImport(Combine)
    import Combine
    import Foundation

    /// NotificationCenter extensions for easier notification handling
    public extension Notification.Name {

        /// Posts a notification with optional object
        /// - Parameter object: Object to include with notification
        func post(object: Any? = nil) {
            NotificationCenter.default.post(name: self, object: object)
        }

        /// Posts a notification with user info and optional object
        /// - Parameters:
        ///   - userInfo: Dictionary of data to include with notification
        ///   - object: Object to include with notification
        func post(
            userInfo: [AnyHashable: Any],
            object: Any? = nil
        ) {
            NotificationCenter.default.post(name: self, object: object, userInfo: userInfo)
        }

        /// Creates a Combine publisher for this notification
        /// - Parameter object: Optional object to filter notifications for
        /// - Returns: A publisher that emits when this notification occurs
        func publisher(object: AnyObject? = nil) -> NotificationCenter.Publisher {
            NotificationCenter.default.publisher(for: self, object: object)
        }
    }

#endif
