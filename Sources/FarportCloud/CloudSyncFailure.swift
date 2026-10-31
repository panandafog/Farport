import CloudKit
import Foundation

public enum CloudSyncFailure {
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        return (value.domain == CKErrorDomain && value.code == CKError.operationCancelled.rawValue) ||
            (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled) ||
            (value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError)
    }
}
