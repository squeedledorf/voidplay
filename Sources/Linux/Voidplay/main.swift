import AppKit

// Voidplay's Linux entry point. The classic skinned player by default; `--cli` runs
// upstream's headless CLI on a plain run loop instead.
registerUpstreamSelectors()

if CommandLine.arguments.contains("--cli") {
    suppressFrameworkLoggingForCLI(verbose: CommandLine.arguments.contains("--verbose"))
    let cli = CLIMode()
    cli.applicationDidFinishLaunching(Notification(name: Notification.Name("VoidplayDidFinishLaunching")))
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
