# Timeouts throw `.timedOut` without a payload

Adding deadlines (`timeout(until:clock:)`) means a timeout is no longer always a duration, and an instant would make the error generic over the clock. Callers only need to know that the operation timed out, so `AsyncOperationError.timeout(Duration)` becomes `.timedOut`, thrown by both the duration and the deadline forms.
