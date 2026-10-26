import AppKit
import CryptoKit
import Foundation
import Sparkle

@MainActor
private final class UpdateProbe: NSObject, SPUUpdaterDelegate {
    var result: String?
    var verifiesDownload = false

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        precondition(item.versionString == "99.0.0")
        if !verifiesDownload { result = "found" }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        preconditionFailure("A tampered update must never reach installation")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        result = "current"
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if verifiesDownload {
            var underlying: NSError? = error as NSError
            var signatureFailure = false
            while let current = underlying {
                if current.domain == SUSparkleErrorDomain
                    && (current.code == SUError.signatureError.rawValue
                        || current.code == SUError.validationError.rawValue) {
                    signatureFailure = true
                }
                underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            precondition(signatureFailure, "Unexpected download failure: \(error)")
            result = "archive-rejected"
        } else if result == nil {
            result = "rejected"
        }
    }
}

@main
struct UpdateTest {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments[1] == "--fixtures" {
            // A disposable key used only by the test server, never the release key.
            let root = URL(fileURLWithPath: arguments[2])
            let key = Curve25519.Signing.PrivateKey()
            try key.rawRepresentation.base64EncodedString().write(
                to: root.appendingPathComponent("test-key"), atomically: true, encoding: .utf8
            )
            try key.publicKey.rawRepresentation.base64EncodedString().write(
                to: root.appendingPathComponent("test-public-key"), atomically: true, encoding: .utf8
            )
            return
        }

        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        let domain = Bundle.main.bundleIdentifier!
        // Each invocation has a unique identifier and cannot change user settings.
        precondition(domain.hasPrefix("com.van-fe.CodeUsage.UpdateTest."))
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        if arguments[1] == "--preferences" {
            let manager = AppUpdateManager()
            precondition(manager.version == "1.0.0")
            precondition(!manager.isStarted && !manager.canCheckForUpdates)
            manager.start()
            precondition(manager.isStarted && manager.startupError == nil)
            precondition(manager.automaticallyChecksForUpdates)
            precondition(manager.automaticallyDownloadsUpdates)
            manager.start() // Starting twice must not create a second updater.
            manager.setAutomaticallyDownloadsUpdates(false)
            manager.setAutomaticallyChecksForUpdates(false)
            precondition(!manager.automaticallyChecksForUpdates)
            precondition(!manager.automaticallyDownloadsUpdates)
            precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
            precondition(UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") as? Bool == false)
            manager.setAutomaticallyChecksForUpdates(true)
            manager.setAutomaticallyDownloadsUpdates(true)
            precondition(manager.automaticallyChecksForUpdates && manager.automaticallyDownloadsUpdates)
            print("Updater defaults, KVO settings, persistence and idempotent startup passed")
        } else if arguments[1] == "--invalid-config" {
            let manager = AppUpdateManager()
            manager.start()
            precondition(!manager.isStarted && manager.startupError != nil)
            precondition(!manager.canCheckForUpdates)
            print("Invalid updater configuration is safely disabled")
        } else if arguments[1] == "--probe" {
            let probe = UpdateProbe()
            probe.verifiesDownload = arguments[2] == "archive-rejected"
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: probe, userDriverDelegate: nil
            )
            try controller.updater.start()
            if probe.verifiesDownload {
                controller.updater.checkForUpdatesInBackground()
            } else {
                controller.updater.checkForUpdateInformation()
            }
            let deadline = Date().addingTimeInterval(15)
            while probe.result == nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            precondition(probe.result == arguments[2], "Unexpected update probe result: \(probe.result ?? "timeout")")
            print("Update feed probe passed: \(arguments[2])")
        }
    }
}
