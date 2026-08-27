import Foundation

@main
struct LiveTest {
    static func main() async {
        let selectedProvider = ProcessInfo.processInfo.environment["CODEUSAGE_LIVE_PROVIDER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if selectedProvider == "qoder" {
            await printResult("Qoder") {
                try await QoderProvider().fetch()
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
                "\($0.title)=\(String(format: "%.1f", $0.usedPercent))%"
            }.joined(separator: ", ")
            print("\(name): OK plan=\(snapshot.planName ?? "unknown") \(metrics)")
        } catch {
            print("\(name): ERROR \(error.localizedDescription)")
        }
    }
}
