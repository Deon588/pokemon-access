import Foundation

/// Runs `work` on the main thread, synchronously, from any thread.
func onMainThread<T>(_ work: () throws -> T) rethrows -> T {
    if Thread.isMainThread {
        return try work()
    }
    return try DispatchQueue.main.sync(execute: work)
}
