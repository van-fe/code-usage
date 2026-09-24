import AppKit

@main
@MainActor
enum CodeUsageApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = CodeUsageAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
