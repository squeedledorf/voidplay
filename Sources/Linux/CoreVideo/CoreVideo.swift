import Foundation
import CoreGraphics

// Linux stand-in for CoreVideo's display link: a timer on the main run loop that calls the output
// callback at the display's refresh rate.
//
// On the main thread, not a thread of its own, because an EGL context (AppKit's NSOpenGLContext
// here) can be current on one thread only: a view makes its context current on the main thread when
// it is created, and a render thread then failed to bind it (EGL_BAD_ACCESS) and projectM
// initialised with no context at all. One thread for every GL call removes the question.
// ponytail: a fixed 60 Hz clock, not the compositor's frame callbacks; render cost lands on the
// main thread, which is fine at visualizer sizes. A per-thread context set would move it off.

public typealias CVReturn = Int32
public let kCVReturnSuccess: CVReturn = 0
public let kCVReturnError: CVReturn = -6660
public typealias CVOptionFlags = UInt64

public struct CVSMPTETime {
    public var subframes: Int16 = 0, subframeDivisor: Int16 = 0, counter: UInt32 = 0, type: UInt32 = 0
    public var flags: UInt32 = 0, hours: Int16 = 0, minutes: Int16 = 0, seconds: Int16 = 0, frames: Int16 = 0
    public init() {}
}

public struct CVTimeStamp {
    public var version: UInt32 = 0
    public var videoTimeScale: Int32 = 0
    public var videoTime: Int64 = 0
    public var hostTime: UInt64 = 0
    public var rateScalar: Double = 1
    public var videoRefreshPeriod: Int64 = 0
    public var smpteTime = CVSMPTETime()
    public var flags: UInt64 = 0
    public var reserved: UInt64 = 0
    public init() {}
}

/// A plain Swift function type: the link is a Swift class here, which C cannot carry, and upstream's
/// callbacks are capture-free closure literals that convert either way.
public typealias CVDisplayLinkOutputCallback = (
    CVDisplayLink, UnsafePointer<CVTimeStamp>, UnsafePointer<CVTimeStamp>, CVOptionFlags,
    UnsafeMutablePointer<CVOptionFlags>, UnsafeMutableRawPointer?) -> CVReturn

public final class CVDisplayLink: @unchecked Sendable {
    fileprivate let lock = NSLock()
    fileprivate var callback: CVDisplayLinkOutputCallback?
    fileprivate var userInfo: UnsafeMutableRawPointer?
    fileprivate var running = false
    private var timer: Timer?
    let period: TimeInterval = 1.0 / 60

    init() {}

    fileprivate func start() {
        lock.lock(); let wasRunning = running; running = true; lock.unlock()
        guard !wasRunning else { return }
        onMain { [self] in
            let timer = Timer(timeInterval: period, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    fileprivate func stop() {
        lock.lock(); running = false; lock.unlock()
        onMain { [self] in timer?.invalidate(); timer = nil }
    }

    private func tick() {
        lock.lock()
        let (live, callback, info) = (running, self.callback, userInfo)
        lock.unlock()
        guard live, let callback else { return }
        var timeStamp = CVTimeStamp()
        timeStamp.hostTime = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        var flagsOut: CVOptionFlags = 0
        _ = callback(self, &timeStamp, &timeStamp, 0, &flagsOut, info)
    }

    private func onMain(_ body: @escaping @Sendable () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.async(execute: body) }
    }
}

@discardableResult
public func CVDisplayLinkCreateWithActiveCGDisplays(_ link: UnsafeMutablePointer<CVDisplayLink?>) -> CVReturn {
    link.pointee = CVDisplayLink()
    return kCVReturnSuccess
}

@discardableResult
public func CVDisplayLinkSetOutputCallback(_ link: CVDisplayLink, _ callback: CVDisplayLinkOutputCallback?,
                                           _ userInfo: UnsafeMutableRawPointer?) -> CVReturn {
    link.lock.lock(); link.callback = callback; link.userInfo = userInfo; link.lock.unlock()
    return kCVReturnSuccess
}

@discardableResult
public func CVDisplayLinkSetCurrentCGDisplay(_ link: CVDisplayLink, _ display: CGDirectDisplayID) -> CVReturn {
    kCVReturnSuccess
}

@discardableResult
public func CVDisplayLinkStart(_ link: CVDisplayLink) -> CVReturn { link.start(); return kCVReturnSuccess }

@discardableResult
public func CVDisplayLinkStop(_ link: CVDisplayLink) -> CVReturn { link.stop(); return kCVReturnSuccess }

public func CVDisplayLinkIsRunning(_ link: CVDisplayLink) -> Bool {
    link.lock.lock(); defer { link.lock.unlock() }
    return link.running
}
