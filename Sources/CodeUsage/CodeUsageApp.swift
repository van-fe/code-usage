import SwiftUI

@main
struct CodeUsageApp: App {
    @NSApplicationDelegateAdaptor(CodeUsageAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
