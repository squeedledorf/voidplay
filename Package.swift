// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Let the compiler find the vendored VLCKit.framework module map (Frameworks/VLCKit.framework)
// so `import VLCKit` resolves. Unsafe flags don't carry over to dependent targets, and the
// swiftbuild build system resolves NullPlayer's imports again while scanning the test target.
let vlcKitSearchPath: SwiftSetting = .unsafeFlags(["-F", "Frameworks"])

#if os(Linux)
// Voidplay: the Linux build. The macOS manifest below is upstream's, untouched.
let package = Package(
    name: "Voidplay",
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.15.4")),
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        // Build tool: rewrites upstream macOS sources for a runtime without Objective-C.
        .executableTarget(name: "voidplay-source-transform", path: "Sources/Linux/SourceTransform"),
        .plugin(
            name: "LinuxSources",
            capability: .buildTool(),
            dependencies: ["voidplay-source-transform"],
            path: "Sources/Linux/LinuxSourcesPlugin"
        ),
        // vDSP stand-in so upstream's `import Accelerate` compiles unchanged.
        .target(name: "Accelerate", path: "Sources/Linux/Accelerate"),
        .systemLibrary(name: "CCairo", path: "Sources/Linux/CCairo", pkgConfig: "cairo"),
        .target(name: "CoreGraphics", dependencies: ["CCairo"], path: "Sources/Linux/CoreGraphics"),
        .systemLibrary(name: "CGdkPixbuf", path: "Sources/Linux/CGdkPixbuf", pkgConfig: "gdk-pixbuf-2.0"),
        .systemLibrary(name: "CGtk", path: "Sources/Linux/CGtk", pkgConfig: "gtk4"),
        .systemLibrary(name: "CX11", path: "Sources/Linux/CX11", pkgConfig: "gtk4-x11"),
        .target(name: "AppKit", dependencies: ["CGdkPixbuf", "CGtk", "CX11", "CoreGraphics", "QuartzCore", "UniformTypeIdentifiers"],
                path: "Sources/Linux/AppKit"),
        .systemLibrary(name: "CMpv", path: "Sources/Linux/CMpv", pkgConfig: "mpv"),
        .systemLibrary(name: "CFFmpeg", path: "Sources/Linux/CFFmpeg", pkgConfig: "libavformat"),
        .target(name: "AVFoundation", dependencies: ["CFFmpeg"], path: "Sources/Linux/AVFoundation"),
        .target(name: "QuartzCore", dependencies: ["CoreGraphics"], path: "Sources/Linux/QuartzCore"),
        .target(name: "CoreImage", dependencies: ["CoreGraphics"], path: "Sources/Linux/CoreImage"),
        .target(name: "UniformTypeIdentifiers", path: "Sources/Linux/UniformTypeIdentifiers"),
        .target(name: "os", path: "Sources/Linux/os"),
        .target(name: "Metal", path: "Sources/Linux/Metal"),
        .target(name: "MetalKit", dependencies: ["Metal"], path: "Sources/Linux/MetalKit"),
        .target(
            name: "CVisClassicCore",
            path: "Sources/CVisClassicCore",
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath(".")]
        ),
        .target(name: "CoreAudio", path: "Sources/Linux/CoreAudio"),
        .target(
            name: "CryptoKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            path: "Sources/Linux/CryptoKit"
        ),
        .target(
            name: "NullPlayerCore",
            // AppKit here is the Linux stand-in; core's `#if canImport(AppKit)` blocks need its colour types.
            dependencies: ["Accelerate", "AppKit"],
            path: "Sources/NullPlayerCore"
        ),
        // Headless player: upstream's portable sources plus Linux replacements in Sources/Linux/Voidplay.
        .executableTarget(
            name: "voidplay",
            dependencies: [
                "NullPlayerCore", "Accelerate", "AppKit", "CMpv", "QuartzCore", "CoreImage", "UniformTypeIdentifiers", "os", "Metal", "MetalKit", "CVisClassicCore", "AVFoundation", "CoreAudio", "CryptoKit", "ZIPFoundation", "FlyingFox",
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources",
            exclude: ["NullPlayer/Resources"],
            sources: [
                "Linux/Voidplay",
            ],
            resources: [.copy("NullPlayer/Resources")],
            swiftSettings: [
                // Darwin's Foundation includes URLSession; on Linux it lives in FoundationNetworking.
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "FoundationNetworking"]),
            ],
            plugins: ["LinuxSources"]
        ),
        .testTarget(
            name: "NullPlayerCoreTests",
            dependencies: ["NullPlayerCore"],
            path: "Tests/NullPlayerCoreTests"
        ),
        .testTarget(
            name: "AVFoundationTests",
            dependencies: ["AVFoundation"],
            path: "Tests/Linux/AVFoundationTests"
        ),
        .testTarget(
            name: "VoidplayTests",
            dependencies: ["voidplay"],
            path: "Tests/Linux/VoidplayTests"
        ),
        .testTarget(
            name: "CoreGraphicsTests",
            dependencies: ["CoreGraphics"],
            path: "Tests/Linux/CoreGraphicsTests"
        ),
        .testTarget(
            name: "SourceTransformTests",
            dependencies: ["voidplay-source-transform"],
            path: "Tests/Linux/SourceTransformTests"
        ),
        .testTarget(
            name: "AppKitTests",
            dependencies: ["AppKit"],
            path: "Tests/Linux/AppKitTests"
        ),
        .testTarget(
            name: "AccelerateTests",
            dependencies: ["Accelerate"],
            path: "Tests/Linux/AccelerateTests"
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
#else
let package = Package(
    name: "NullPlayer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NullPlayer", targets: ["NullPlayer"])
    ],
    dependencies: [
        // ZIP extraction for .wsz skin files
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        // SQLite for media library — pinned to 0.15.x; 0.16+ changed Expression<T> init API
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", .upToNextMinor(from: "0.15.4")),
        // Video playback uses the vendored VLCKit.framework (LGPL) in Frameworks/,
        // linked via unsafeFlags on the NullPlayer target — not an SPM dependency.
        // Audio streaming with AVAudioEngine support (for Plex EQ)
        .package(url: "https://github.com/dimitris-c/AudioStreaming.git", from: "1.4.0"),
        // Lightweight HTTP server for local file casting
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "CVisClassicCore",
            dependencies: [],
            path: "Sources/CVisClassicCore",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath(".")
            ]
        ),
        .target(
            name: "CTripexCore",
            dependencies: [],
            path: "Sources/CTripexCore",
            // D3D9 + Win32 + WaveOut TUs replaced by upstream_port/
            // RendererOpenGL + HostAudioSource (Chunks 3–4). main.cpp is a
            // Win32 message-loop shell with no logic to re-home — Tripex's
            // beat/fade/effect-switching state lives on the Tripex class.
            exclude: [
                "upstream/main.cpp",
                "upstream/RendererDirect3d.cpp",
                "upstream/RendererDirect3d.h",
                "upstream/AudioDevice.cpp",
                "upstream/AudioDevice.h",
                "upstream/LICENSE",
                "upstream/README.md",
                "upstream/Dll.vcxproj",
                "upstream/Tripex.vcxproj",
                "upstream/Tripex.vcxproj.filters",
                "upstream/packages.config",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream_port"),
                .define("__APPLE__"),
                .unsafeFlags(["-fno-strict-aliasing", "-fwrapv"])
            ],
            linkerSettings: [
                // RendererOpenGL.cpp uses ImageIO + CoreGraphics to decode
                // upstream's embedded JPEG textures.
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                // OpenGL is deprecated on macOS 10.14+ but still ships;
                // link explicitly rather than relying on transitive linkage
                // from Swift's `import OpenGL.GL3`.
                .linkedFramework("OpenGL"),
            ]
        ),
        .target(
            name: "CGeissCore",
            dependencies: [],
            path: "Sources/CGeissCore",
            // Phase 4c: helper.cpp + proc_map.cpp + upstream_port/geiss_port.cpp
            // are in the compile set. The upstream main.cpp stays excluded —
            // it is a Win32/DirectDraw orchestrator, retained in tree for
            // licence + reference; the platform-neutral algorithms are pulled
            // into the build via `geiss_port.cpp` (which #includes Effects.h
            // and ports the orchestration functions). The phase-4b stub block
            // inside proc_map.cpp is no longer the global-definition site —
            // geiss_port.cpp owns them — so `GEISS_PHASE_4B_STUBS` is dropped.
            exclude: [
                "upstream/main.cpp",
                "upstream/LICENSE",
                "upstream/README.md",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("upstream"),
                .headerSearchPath("upstream_port"),
                .define("__APPLE__"),
                .unsafeFlags(["-fno-strict-aliasing", "-fwrapv"])
            ]
        ),
        // Lightweight core library containing model types
        // Unit tests depend only on this target for fast compilation
        .target(
            name: "NullPlayerCore",
            dependencies: [],
            path: "Sources/NullPlayerCore"
        ),
        .target(
            name: "ObjCExceptionCatcher",
            dependencies: [],
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        // System library target for libprojectM (ProjectM visualization)
        // To enable projectM support:
        // 1. Build libprojectM v4.1.6+ as a universal binary
        // 2. Place libprojectM-4.dylib in Frameworks/
        // 3. Uncomment the CProjectM dependency in the NullPlayer target
        .systemLibrary(
            name: "CProjectM",
            path: "Frameworks/libprojectm-4",
            pkgConfig: nil,
            providers: []
        ),
        // System library target for libaubio (BPM/tempo detection)
        .systemLibrary(
            name: "CAubio",
            path: "Frameworks/libaubio",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "NullPlayer",
            dependencies: [
                "NullPlayerCore",
                "ObjCExceptionCatcher",
                "CVisClassicCore",
                "CGeissCore",
                "CTripexCore",
                "ZIPFoundation",
                .product(name: "SQLite", package: "SQLite.swift"),
                "AudioStreaming",
                "CProjectM",
                "CAubio",
                "FlyingFox",
            ],
            path: "Sources/NullPlayer",
            resources: [
                .copy("Resources"),
                .copy("Visualization/SpectrumShaders.metal"),
                .copy("Visualization/SpectrogramShaders.metal"),
                .copy("Visualization/FlameShaders.metal"),
                .copy("Visualization/CosmicShaders.metal"),
                .copy("Visualization/ElectricityShaders.metal"),
                .copy("Visualization/MatrixShaders.metal"),
                .copy("Visualization/SnowShaders.metal"),
                .copy("Visualization/EKGShaders.metal"),
                .copy("ModernSkin/BloomShader.metal")
            ],
            swiftSettings: [vlcKitSearchPath],
            linkerSettings: [
                .linkedFramework("WebKit"),
                // The WMP skin engine runs skin JScript in an in-process JSContext whose only
                // reachable surface is `WMPObjectModel`; see the wmp-skin-guide skill.
                .linkedFramework("JavaScriptCore"),
                .unsafeFlags([
                    "-L", "Frameworks",
                    "-L", "/opt/homebrew/lib",
                    // Link the vendored VLCKit.framework (LGPL video engine).
                    "-F", "Frameworks",
                    "-framework", "VLCKit",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "NullPlayerCoreTests",
            dependencies: [
                "NullPlayerCore"
            ],
            path: "Tests/NullPlayerCoreTests"
        ),
        .testTarget(
            name: "NullPlayerAppTests",
            dependencies: [
                "NullPlayer",
                "ZIPFoundation"
            ],
            path: "Tests/NullPlayerAppTests",
            // Committed golden PNGs for the `.wal` render sweep. They are read from the source tree
            // by path (so an update run rewrites them in place), not from a resource bundle.
            exclude: ["Fixtures", "Goldens"],
            swiftSettings: [vlcKitSearchPath],
            // The test bundle links NullPlayer's vendored libraries (VLCKit, projectM, aubio);
            // let it load them from Frameworks/ instead of from a hand-made build-dir symlink.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", Context.packageDirectory + "/Frameworks"]),
            ]
        ),
    ],
    // Use Swift 5 language mode to keep concurrency warnings as warnings, not errors
    // This allows gradual adoption of strict concurrency without blocking builds
    swiftLanguageModes: [.v5],
    // CTripexCore uses std::shared_ptr<T[]> (C++17). C++17 is backwards
    // compatible with CGeissCore / CVisClassicCore code.
    cxxLanguageStandard: .cxx17
)
#endif
