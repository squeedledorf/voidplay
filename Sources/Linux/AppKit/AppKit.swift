// Linux: headless stand-ins for the AppKit types the portable sources touch.
@_exported import Foundation

/// Lifecycle protocol only; Linux has no NSApplication, so main.swift calls the delegate itself.
public protocol NSApplicationDelegate: AnyObject {}
