import Foundation

// MARK: - 线程安全锁

final class UnfairLock {
    private var _lock = os_unfair_lock()
    func lock() { os_unfair_lock_lock(&_lock) }
    func unlock() { os_unfair_lock_unlock(&_lock) }
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        let result = body()
        unlock()
        return result
    }
}
