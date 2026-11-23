import Foundation

@main
struct LiveTest {
    static func main() async {
        let selectedProvider = ProcessInfo.processInfo.environment["CODEUSAGE_LIVE_PROVIDER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if selectedProvider == "devin" {
            await printResult("Devin") { try await DevinProvider().fetch() }
            return
        }
        if selectedProvider == "deepseek" {
            await printResult("DeepSeek Harness") { try await DeepSeekProvider().fetch() }
            return
        }

        if selectedProvider == "qoder" {
            await printResult("Qoder") {
                try await QoderProvider().fetch()
            }
            return
        }

        if selectedProvider == "cursor-cache" {
            let counter = CursorKeychainReadCounter()
            let credentials = CursorCredentialStore(readPassword: { try counter.password() })
            let provider = CursorProvider(credentials: credentials)
            do {
                for index in 1...3 {
                    let snapshot = try await provider.fetch()
                    print("Cursor fetch \(index): OK plan=\(snapshot.planName ?? "unknown")")
                }
                guard counter.count == 1 else {
                    print("Cursor cache: FAIL Keychain reads=\(counter.count)")
                    exit(1)
                }
                print("Cursor cache: PASS 3 real usage fetches, 1 Keychain read")
            } catch {
                print("Cursor cache: ERROR \(error.localizedDescription)")
                exit(1)
            }
            return
        }

        if selectedProvider == "cursor" {
            await printResult("Cursor") {
                try await CursorProvider().fetch()
            }
            return
        }

        await printResult("Codex") {
            try await CodexProvider().fetch()
        }
        await printResult("Cursor") {
            try await CursorProvider().fetch()
        }
        if ProviderInstallation.isInstalled(.claude) {
            await printResult("Claude Code") {
                try await ClaudeCodeProvider().fetch()
            }
        }
        if ProviderInstallation.isInstalled(.kiro) {
            await printResult("Kiro") {
                try await KiroProvider().fetch()
            }
        }
        if ProviderInstallation.isInstalled(.devin) {
            await printResult("Devin") { try await DevinProvider().fetch() }
        }
        if ProviderInstallation.isInstalled(.deepseek) {
            await printResult("DeepSeek Harness") { try await DeepSeekProvider().fetch() }
        }
        if ProviderInstallation.isInstalled(.qoder) {
            await printResult("Qoder") {
                try await QoderProvider().fetch()
            }
        }
    }

    private static func printResult(
        _ name: String,
        operation: () async throws -> ProviderSnapshot
    ) async {
        do {
            let snapshot = try await operation()
            let metrics = snapshot.metrics.map {
                if $0.showsProgress {
                    return "\($0.title)=\(String(format: "%.1f", $0.usedPercent))%"
                }
                return "\($0.title)=\(UsageMetricDisplayFormatter.valueText($0, provider: snapshot.provider, snapshot: snapshot) ?? "unknown")"
            }.joined(separator: ", ")
            print("\(name): OK plan=\(snapshot.planName ?? "unknown") \(metrics)")
        } catch {
            print("\(name): ERROR \(error.localizedDescription)")
        }
    }
}

private final class CursorKeychainReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func password() throws -> Data {
        lock.lock()
        reads += 1
        lock.unlock()
        return try CursorCredentialCodec.keychainPassword()
    }
}
