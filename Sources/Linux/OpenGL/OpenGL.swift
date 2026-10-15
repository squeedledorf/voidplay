@_exported import COpenGL
import Foundation

// Linux stand-in for OpenGL.framework: the GL entry points (glvnd's libOpenGL, current through
// EGL — see AppKit's NSOpenGLContext) plus the CGL context lock upstream takes around a frame.

/// A CGL context object: here only the lock, which AppKit's NSOpenGLContext owns one of.
public final class CGLContextLock: @unchecked Sendable {
    let lock = NSRecursiveLock()
    public init() {}
}

public typealias CGLContextObj = CGLContextLock
public typealias CGLError = Int32
public let kCGLNoError: CGLError = 0

@discardableResult
public func CGLLockContext(_ context: CGLContextObj) -> CGLError { context.lock.lock(); return kCGLNoError }

@discardableResult
public func CGLUnlockContext(_ context: CGLContextObj) -> CGLError { context.lock.unlock(); return kCGLNoError }
