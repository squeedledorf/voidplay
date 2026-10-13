// Linux stand-in for the slice of Apple's `os` module the app uses.
@_exported import Foundation

/// A lock guarding a value, as os's OSAllocatedUnfairLock (an NSLock underneath).
public struct OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private final class Box {
        let lock = NSLock()
        var state: State
        init(_ state: State) { self.state = state }
    }

    private let box: Box

    public init(initialState: State) { box = Box(initialState) }

    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        box.lock.lock()
        defer { box.lock.unlock() }
        return try body(&box.state)
    }

    public func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R { try withLock(body) }
    public func lock() { box.lock.lock() }
    public func unlock() { box.lock.unlock() }
}

extension OSAllocatedUnfairLock where State == Void {
    public init() { self.init(initialState: ()) }
    public func withLock<R>(_ body: () throws -> R) rethrows -> R { try withLock { (_: inout Void) in try body() } }
}
