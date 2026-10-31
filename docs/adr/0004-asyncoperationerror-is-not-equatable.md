# `AsyncOperationError` is not `Equatable`

The custom `==` compared `maxRetriesExceeded` by attempt count and ignored `lastError`, so failures with unrelated causes compared equal. Equality that silently drops part of the value is a trap in a public API, and errors carrying `any Error` cannot be compared faithfully. We remove the conformance; callers match with `if case`.
