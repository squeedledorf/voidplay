import Foundation

// Voidplay's Linux entry point: upstream's headless CLI on a plain run loop. The GTK
// interface arrives in a later stage; until then every launch is CLI mode.
suppressFrameworkLoggingForCLI(verbose: CommandLine.arguments.contains("--verbose"))
let cli = CLIMode()
cli.applicationDidFinishLaunching(Notification(name: Notification.Name("VoidplayDidFinishLaunching")))
RunLoop.main.run()
