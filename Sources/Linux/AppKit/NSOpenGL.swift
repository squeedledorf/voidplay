import Foundation
import CoreGraphics
import CEGL
import OpenGL

// (EGL's EGL_NO_DISPLAY/CONTEXT/SURFACE are null pointers, which Swift spells nil.)
// Linux stand-in for AppKit's OpenGL classes, on EGL with Mesa's surfaceless platform: every
// context draws into its own pbuffer (framebuffer 0, as an on-screen NSOpenGLView's is), and
// `flushBuffer` reads the frame back and has the view draw it like any other image. No GL surface
// is ever embedded in a GTK window, so a GL view stacks, clips and composites with the skin's
// artwork exactly as a drawn view does.
//
// ponytail: a readback per presented frame (a few MB/s at visualizer sizes); a GtkGLArea-backed
// view would avoid it if a large fullscreen visualizer ever shows up in a profile.

public typealias NSOpenGLPixelFormatAttribute = UInt32
public let NSOpenGLPFAAccelerated = 73
public let NSOpenGLPFADoubleBuffer = 5
public let NSOpenGLPFAColorSize = 8
public let NSOpenGLPFAAlphaSize = 11
public let NSOpenGLPFADepthSize = 12
public let NSOpenGLPFAStencilSize = 13
public let NSOpenGLPFAOpenGLProfile = 99
public let NSOpenGLPFAMultisample = 59
public let NSOpenGLPFASampleBuffers = 55
public let NSOpenGLPFASamples = 56
public let NSOpenGLProfileVersionLegacy = 0x1000
public let NSOpenGLProfileVersion3_2Core = 0x3200
public let NSOpenGLProfileVersion4_1Core = 0x4100

/// The attributes are recorded, not negotiated: every context here is GL 3.3+ core with
/// RGBA8, depth 24 and stencil 8, which is what upstream asks for (projectM needs the stencil).
public final class NSOpenGLPixelFormat: @unchecked Sendable {
    public let attributes: [NSOpenGLPixelFormatAttribute]
    public init?(attributes: [NSOpenGLPixelFormatAttribute]) {
        guard EGLRuntime.shared != nil else { return nil }
        self.attributes = attributes
    }
}

/// The process's EGL display and config, made once.
final class EGLRuntime: @unchecked Sendable {
    let display: EGLDisplay
    let config: EGLConfig

    nonisolated(unsafe) static let shared: EGLRuntime? = EGLRuntime()

    private init?() {
        guard let display = cegl_surfaceless_display() else {
            NSLog("NSOpenGL: no EGL surfaceless display (Mesa's EGL_MESA_platform_surfaceless)")
            return nil
        }
        var major: EGLint = 0, minor: EGLint = 0
        guard eglInitialize(display, &major, &minor) == EGLBoolean(EGL_TRUE),
              eglBindAPI(EGLenum(EGL_OPENGL_API)) == EGLBoolean(EGL_TRUE) else {
            NSLog("NSOpenGL: EGL initialisation failed (0x%x)", eglGetError())
            return nil
        }
        let attributes: [EGLint] = [
            EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
            EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8, EGL_NONE,
        ]
        var config: EGLConfig?
        var count: EGLint = 0
        guard eglChooseConfig(display, attributes, &config, 1, &count) == EGLBoolean(EGL_TRUE),
              count > 0, let config else {
            NSLog("NSOpenGL: no RGBA8/D24S8 pbuffer config for desktop GL")
            return nil
        }
        self.display = display
        self.config = config
    }
}

public final class NSOpenGLContext: @unchecked Sendable {
    public enum Parameter { case swapInterval, surfaceOpacity, surfaceOrder }

    public let pixelFormat: NSOpenGLPixelFormat
    let context: EGLContext
    private var surface: EGLSurface?
    private var surfaceSize = (width: 0, height: 0)
    private let cgl = CGLContextLock()
    /// The size framebuffer 0 should have: the attached view's backing size.
    private let sizeLock = NSLock()
    private var wantedSize = (width: 16, height: 16)
    weak var view: NSOpenGLView?

    nonisolated(unsafe) private static var currentByThread: [ObjectIdentifier: NSOpenGLContext] = [:]
    private static let currentLock = NSLock()

    public init?(format: NSOpenGLPixelFormat, share: NSOpenGLContext?) {
        guard let runtime = EGLRuntime.shared else { return nil }
        let attributes: [EGLint] = [
            EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 3,
            EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE,
        ]
        guard let context = eglCreateContext(runtime.display, runtime.config,
                                             share?.context, attributes) else {
            NSLog("NSOpenGL: eglCreateContext failed (0x%x)", eglGetError())
            return nil
        }
        self.context = context
        pixelFormat = format
    }

    deinit {
        guard let runtime = EGLRuntime.shared else { return }
        if let surface { eglDestroySurface(runtime.display, surface) }
        eglDestroyContext(runtime.display, context)
    }

    public var cglContextObj: CGLContextObj? { cgl }

    public static var current: NSOpenGLContext? {
        currentLock.lock(); defer { currentLock.unlock() }
        return currentByThread[ObjectIdentifier(Thread.current)]
    }

    public static func clearCurrentContext() {
        guard let runtime = EGLRuntime.shared else { return }
        eglMakeCurrent(runtime.display, nil, nil, nil)
        currentLock.lock(); currentByThread[ObjectIdentifier(Thread.current)] = nil; currentLock.unlock()
    }

    func setSurfaceSize(width: Int, height: Int) {
        sizeLock.lock(); wantedSize = (max(1, width), max(1, height)); sizeLock.unlock()
    }

    /// Current on this thread, with framebuffer 0 at the view's size (a new pbuffer when it moved).
    public func makeCurrentContext() {
        guard let runtime = EGLRuntime.shared else { return }
        sizeLock.lock(); let wanted = wantedSize; sizeLock.unlock()
        if surface == nil || surfaceSize != wanted {
            let attributes: [EGLint] = [EGL_WIDTH, EGLint(wanted.width), EGL_HEIGHT, EGLint(wanted.height), EGL_NONE]
            if let fresh = eglCreatePbufferSurface(runtime.display, runtime.config, attributes) {
                if let old = surface { eglDestroySurface(runtime.display, old) }
                surface = fresh
                surfaceSize = wanted
            } else {
                NSLog("NSOpenGL: pbuffer %dx%d failed (0x%x)", wanted.width, wanted.height, eglGetError())
            }
        }
        guard let surface else { return }
        if eglMakeCurrent(runtime.display, surface, surface, context) != EGLBoolean(EGL_TRUE) {
            NSLog("NSOpenGL: eglMakeCurrent failed (0x%x)", eglGetError())
            return
        }
        Self.currentLock.lock(); Self.currentByThread[ObjectIdentifier(Thread.current)] = self; Self.currentLock.unlock()
    }

    public func setValues(_ values: UnsafePointer<GLint>, for parameter: Parameter) {}
    public func update() {}

    /// "Swaps" by reading framebuffer 0 back and handing the frame to the view.
    public func flushBuffer() {
        guard let view, surfaceSize.width > 0 else { return }
        let (width, height) = surfaceSize
        var previous: GLint = 0
        glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &previous)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), 0)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)
        pixels.withUnsafeMutableBytes {
            glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
        }
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(previous))
        // GL rows run bottom-up; an image's run top-down.
        let row = width * 4
        var flipped = [UInt8](repeating: 0, count: pixels.count)
        for y in 0..<height {
            flipped.replaceSubrange(y * row..<(y + 1) * row, with: pixels[(height - 1 - y) * row..<(height - y) * row])
        }
        guard let provider = CGDataProvider(data: Data(flipped)) else { return }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder32Big),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        view.present(image)
    }
}

/// A view whose content is a GL context's framebuffer 0, shown as the last flushed frame.
open class NSOpenGLView: NSView {
    open var pixelFormat: NSOpenGLPixelFormat?
    open var openGLContext: NSOpenGLContext? {
        didSet { openGLContext?.view = self; updateSurfaceSize() }
    }
    open var wantsBestResolutionOpenGLSurface = false

    // Written from the render thread (`present`), read on the main thread (`draw`).
    private nonisolated let frameLock = NSLock()
    private nonisolated(unsafe) var frameImage: CGImage?
    private nonisolated(unsafe) var redrawQueued = false

    public init?(frame frameRect: NSRect, pixelFormat format: NSOpenGLPixelFormat?) {
        super.init(frame: frameRect)
        let format = format ?? NSOpenGLPixelFormat(attributes: [])
        pixelFormat = format
        if let format { openGLContext = NSOpenGLContext(format: format, share: nil) }
        openGLContext?.view = self
        updateSurfaceSize()
    }

    public required init?(coder: NSCoder) { nil }

    open override var frame: NSRect {
        didSet {
            guard frame.size != oldValue.size else { return }
            updateSurfaceSize()
            reshape()
        }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        let backing = convertToBacking(bounds)
        openGLContext?.setSurfaceSize(width: Int(backing.width.rounded()), height: Int(backing.height.rounded()))
    }

    open func reshape() {}
    open func update() { openGLContext?.update() }
    open func prepareOpenGL() {}
    open func clearGLContext() {}

    /// From the render thread: keep the frame, redraw on the main thread (coalesced).
    nonisolated func present(_ image: CGImage?) {
        frameLock.lock()
        frameImage = image
        let queue = !redrawQueued
        redrawQueued = true
        frameLock.unlock()
        guard queue else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frameLock.lock(); self.redrawQueued = false; self.frameLock.unlock()
                self.needsDisplay = true
            }
        }
    }

    open override func draw(_ dirtyRect: NSRect) {
        frameLock.lock(); let image = frameImage; frameLock.unlock()
        guard let image, let context = NSGraphicsContext.current?.cgContext else {
            NSColor.black.setFill(); bounds.fill(); return
        }
        context.saveGState()
        if isFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        context.interpolationQuality = .low
        context.draw(image, in: bounds)
        context.restoreGState()
    }
}
