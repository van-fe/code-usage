import AppKit
import Combine
import Sparkle

/// Sparkle owns version comparison, authenticated downloads, installation,
/// authorization when needed, and relaunching the menu bar app.
@MainActor
final class AppUpdateManager: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var isStarted = false
    @Published private(set) var startupError: String?

    let version: String
    var willShowUpdateUI: (() -> Void)?
    private let controller: SPUStandardUpdaterController

    init() {
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloadsUpdates)
    }

    func start() {
        guard !isStarted else { return }
        // `swift run` has no packaged Info.plist or installation destination.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            try controller.updater.start()
            isStarted = true
            startupError = nil
        } catch {
            startupError = L10n.text("无法启动应用更新")
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        willShowUpdateUI?()
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isStarted else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard isStarted else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
    }
}
