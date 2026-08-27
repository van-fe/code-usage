import Foundation

enum SubscriptionCategory: String, CaseIterable, Identifiable, Equatable, Sendable {
    case freeTrial
    case individual
    case team
    case enterprise
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeTrial: return "免费试用"
        case .individual: return "个人用户"
        case .team: return "团队用户"
        case .enterprise: return "企业用户"
        case .unknown: return "未知订阅"
        }
    }

    var hasSharedOrganizationContext: Bool {
        self == .team || self == .enterprise
    }

    static func inferred(from planName: String?) -> SubscriptionCategory {
        let normalized = planName?
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return .unknown }
        if normalized.contains("enterprise") || normalized == "edu" {
            return .enterprise
        }
        if normalized.contains("team") ||
            normalized.contains("business") ||
            normalized.contains("organization") ||
            normalized.contains("organisation") {
            return .team
        }
        if normalized.contains("trial") ||
            normalized == "free" ||
            normalized.contains("hobby") {
            return .freeTrial
        }
        return .individual
    }
}

enum ProviderKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case codex
    case cursor
    case claude
    case kiro
    case qoder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .claude: return "Claude Code"
        case .kiro: return "Kiro"
        case .qoder: return "Qoder"
        }
    }

    var shortTitle: String {
        switch self {
        case .codex: return "C"
        case .cursor: return "↗"
        case .claude: return "CC"
        case .kiro: return "K"
        case .qoder: return "Q"
        }
    }

    var menuBarPreferenceKey: String {
        "menuBar.\(rawValue)"
    }
}

enum ProviderArchive {
    static func decode(_ rawValues: [String]) -> Set<ProviderKind> {
        Set(rawValues.compactMap(ProviderKind.init(rawValue:)))
    }

    static func encode(_ providers: Set<ProviderKind>) -> [String] {
        ProviderKind.allCases
            .filter(providers.contains)
            .map(\.rawValue)
    }
}

enum ProviderInstallation {
    static func installedProviders() -> [ProviderKind] {
        ProviderKind.allCases.filter(isInstalled)
    }

    static func isInstalled(_ provider: ProviderKind) -> Bool {
        switch provider {
        case .codex:
            return hasExecutable([
                "/Applications/ChatGPT.app/Contents/Resources/codex",
                "/Applications/Codex.app/Contents/MacOS/Codex",
                "~/.local/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ], named: "codex")
        case .cursor:
            return FileManager.default.fileExists(atPath: "/Applications/Cursor.app") ||
                FileManager.default.fileExists(atPath: expandedHome(
                    "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
                ))
        case .claude:
            return hasExecutable([
                "~/.local/bin/claude",
                "~/.claude/local/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"
            ], named: "claude")
        case .kiro:
            return FileManager.default.fileExists(atPath: "/Applications/Kiro.app") ||
                FileManager.default.fileExists(atPath: expandedHome("~/Applications/Kiro.app")) ||
                FileManager.default.fileExists(atPath: "/Applications/Kiro CLI.app") ||
                FileManager.default.fileExists(atPath: expandedHome("~/Applications/Kiro CLI.app")) ||
                FileManager.default.fileExists(atPath: expandedHome(
                    "~/Library/Application Support/kiro-cli/data.sqlite3"
                )) ||
                hasExecutable([
                    "/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli",
                    "~/.local/bin/kiro-cli",
                    "/opt/homebrew/bin/kiro-cli",
                    "/usr/local/bin/kiro-cli"
                ], named: "kiro-cli") || hasExecutable([
                    "~/.local/bin/kiro",
                    "/opt/homebrew/bin/kiro",
                    "/usr/local/bin/kiro"
                ], named: "kiro")
        case .qoder:
            let fileManager = FileManager.default
            return isQoderInstalled(
                environment: ProcessInfo.processInfo.environment,
                fileExists: { fileManager.fileExists(atPath: $0) },
                isExecutable: { ProcessUtils.isExecutableRegularFile(atPath: $0) }
            )
        }
    }

    static func loginCommand(for provider: ProviderKind) -> String? {
        switch provider {
        case .codex:
            return loginCommand(
                named: "codex",
                candidates: [
                    "~/.local/bin/codex",
                    "/opt/homebrew/bin/codex",
                    "/usr/local/bin/codex",
                    "/usr/bin/codex"
                ],
                arguments: "login"
            )
        case .cursor:
            return nil
        case .claude:
            return loginCommand(
                named: "claude",
                candidates: [
                    "~/.local/bin/claude",
                    "~/.claude/local/claude",
                    "/opt/homebrew/bin/claude",
                    "/usr/local/bin/claude"
                ],
                arguments: "auth login"
            )
        case .kiro:
            return loginCommand(
                named: "kiro-cli",
                candidates: [
                    "/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli",
                    "~/.local/bin/kiro-cli",
                    "/opt/homebrew/bin/kiro-cli",
                    "/usr/local/bin/kiro-cli"
                ],
                arguments: "login"
            ) ?? loginCommand(
                named: "kiro",
                candidates: [
                    "~/.local/bin/kiro",
                    "/opt/homebrew/bin/kiro",
                    "/usr/local/bin/kiro"
                ],
                arguments: "login"
            )
        case .qoder:
            let environment = ProcessInfo.processInfo.environment
            var qoderCLICandidates: [String] = []
            if let override = environment["QODERCLI_PATH"], !override.isEmpty {
                qoderCLICandidates.append(override)
            }
            if let cliHome = environment["QODER_CLI_HOME"], !cliHome.isEmpty {
                qoderCLICandidates.append("\(cliHome)/.qoder/local/qodercli")
            }
            qoderCLICandidates += [
                "~/.qoder/local/qodercli",
                "~/.qoder/bin/qodercli",
                "~/.local/bin/qodercli",
                "/opt/homebrew/bin/qodercli",
                "/usr/local/bin/qodercli",
                "/usr/bin/qodercli"
            ]
            if let command = loginCommand(
                named: "qodercli",
                candidates: qoderCLICandidates,
                arguments: "login"
            ) {
                return command
            }
            return loginCommand(
                named: "qoder",
                candidates: [
                    "~/.qoder/local/qoder",
                    "~/.qoder/bin/qoder",
                    "~/.local/bin/qoder",
                    "/opt/homebrew/bin/qoder",
                    "/usr/local/bin/qoder",
                    "/usr/bin/qoder"
                ],
                arguments: "login"
            )
        }
    }

    static func cliExecutable(for provider: ProviderKind) -> String? {
        switch provider {
        case .codex:
            return executable(
                named: "codex",
                candidates: [
                    "~/.local/bin/codex",
                    "/Applications/ChatGPT.app/Contents/Resources/codex",
                    "/Applications/Codex.app/Contents/MacOS/Codex",
                    "/opt/homebrew/bin/codex",
                    "/usr/local/bin/codex",
                    "/usr/bin/codex"
                ]
            )
        case .cursor:
            // Cursor's `cursor`/`code` launchers open the IDE; they are not an
            // interactive agent CLI, so the IDE action handles this provider.
            return nil
        case .claude:
            return executable(
                named: "claude",
                candidates: [
                    "~/.local/bin/claude",
                    "~/.claude/local/claude",
                    "/opt/homebrew/bin/claude",
                    "/usr/local/bin/claude",
                    "/usr/bin/claude"
                ]
            )
        case .kiro:
            return executable(
                named: "kiro-cli",
                candidates: [
                    "/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli",
                    "~/.local/bin/kiro-cli",
                    "/opt/homebrew/bin/kiro-cli",
                    "/usr/local/bin/kiro-cli"
                ]
            )
        case .qoder:
            let environment = ProcessInfo.processInfo.environment
            var qoderCLICandidates: [String] = []
            if let override = environment["QODERCLI_PATH"], !override.isEmpty {
                qoderCLICandidates.append(override)
            }
            if let cliHome = environment["QODER_CLI_HOME"], !cliHome.isEmpty {
                qoderCLICandidates.append("\(cliHome)/.qoder/local/qodercli")
            }
            qoderCLICandidates += [
                "~/.qoder/local/qodercli",
                "~/.qoder/bin/qodercli",
                "~/.local/bin/qodercli",
                "/opt/homebrew/bin/qodercli",
                "/usr/local/bin/qodercli",
                "/usr/bin/qodercli"
            ]
            if let executable = executable(
                named: "qodercli",
                candidates: qoderCLICandidates
            ) {
                return executable
            }
            return executable(
                named: "qoder",
                candidates: [
                    "~/.qoder/local/qoder",
                    "~/.qoder/bin/qoder",
                    "~/.local/bin/qoder",
                    "/opt/homebrew/bin/qoder",
                    "/usr/local/bin/qoder",
                    "/usr/bin/qoder"
                ]
            )
        }
    }

    static func isQoderInstalled(
        environment: [String: String],
        fileExists: (String) -> Bool,
        isExecutable: (String) -> Bool
    ) -> Bool {
        let installations = [
            "/Applications/Qoder IDE.app",
            "/Applications/Qoder.app",
            expandedHome("~/Applications/Qoder IDE.app"),
            expandedHome("~/Applications/Qoder.app"),
            expandedHome("~/Library/Application Support/Qoder/SharedClientCache/.info.json")
        ]
        if installations.contains(where: fileExists) { return true }

        var executables: [String] = []
        if let override = environment["QODERCLI_PATH"], !override.isEmpty {
            executables.append(expandedHome(override))
        }
        if let cliHome = environment["QODER_CLI_HOME"], !cliHome.isEmpty {
            let expandedCLIHome = expandedHome(cliHome)
            executables += [
                "\(expandedCLIHome)/.qoder/local/qodercli",
                "\(expandedCLIHome)/.qoder/local/qoder"
            ]
        }
        executables += [
            expandedHome("~/.qoder/local/qodercli"),
            expandedHome("~/.qoder/local/qoder"),
            expandedHome("~/.qoder/bin/qodercli"),
            expandedHome("~/.qoder/bin/qoder"),
            expandedHome("~/.local/bin/qodercli"),
            expandedHome("~/.local/bin/qoder"),
            "/opt/homebrew/bin/qodercli",
            "/opt/homebrew/bin/qoder",
            "/usr/local/bin/qodercli",
            "/usr/local/bin/qoder",
            "/usr/bin/qodercli",
            "/usr/bin/qoder"
        ]
        if let searchPath = environment["PATH"] {
            for directory in searchPath.split(separator: ":") {
                executables.append("\(directory)/qodercli")
                executables.append("\(directory)/qoder")
            }
        }
        return executables.contains(where: isExecutable)
    }

    private static func hasExecutable(_ candidates: [String], named name: String) -> Bool {
        executable(named: name, candidates: candidates) != nil
    }

    private static func executable(named name: String, candidates: [String]) -> String? {
        var paths = candidates.map(expandedHome)
        if let searchPath = ProcessInfo.processInfo.environment["PATH"] {
            paths += searchPath.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(name).path
            }
        }
        return paths.first(where: { ProcessUtils.isExecutableRegularFile(atPath: $0) })
    }

    private static func loginCommand(
        named name: String,
        candidates: [String],
        arguments: String
    ) -> String? {
        if let searchPath = ProcessInfo.processInfo.environment["PATH"],
           searchPath.split(separator: ":").contains(where: { directory in
               let path = URL(fileURLWithPath: String(directory))
                   .appendingPathComponent(name).path
               return ProcessUtils.isExecutableRegularFile(atPath: path)
           }) {
            return "\(name) \(arguments)"
        }
        guard let executable = candidates.lazy
            .map(expandedHome)
            .first(where: { ProcessUtils.isExecutableRegularFile(atPath: $0) })
        else { return nil }
        return "\(shellQuoted(executable)) \(arguments)"
    }

    private static func shellQuoted(_ value: String) -> String {
        guard !value.allSatisfy({ $0.isLetter || $0.isNumber || "/._-".contains($0) })
        else { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func expandedHome(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2))).path
    }
}

enum UsageMetricValue: Equatable, Sendable {
    case usd(usedCents: Int64, limitCents: Int64?)
    case quantity(used: Double?, limit: Double?, remaining: Double?, unit: String)
}

struct UsageMetric: Identifiable, Equatable, Sendable {
    enum DeadlineKind: Equatable, Sendable {
        case reset
        case expiration
    }

    enum Group: String, Equatable, Sendable {
        case included
        case onDemand
        case credits
        case personalAddOn
        case organizationShared

        var title: String {
            switch self {
            case .included: return "套餐内用量"
            case .onDemand: return "按量付费"
            case .credits: return "额外 Credits"
            case .personalAddOn: return "个人加购额度"
            case .organizationShared: return "组织共享额度"
            }
        }
    }

    let id: String
    let title: String
    let usedPercent: Double
    let deadlineAt: Date?
    let deadlineKind: DeadlineKind
    let windowDuration: TimeInterval?
    let group: Group?
    let value: UsageMetricValue?
    let showsProgress: Bool
    let allowsLimitEditing: Bool

    init(
        id: String,
        title: String,
        usedPercent: Double,
        deadlineAt: Date?,
        deadlineKind: DeadlineKind = .reset,
        windowDuration: TimeInterval? = nil,
        group: Group? = nil,
        value: UsageMetricValue? = nil,
        showsProgress: Bool = true,
        allowsLimitEditing: Bool = false
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.deadlineAt = deadlineAt
        self.deadlineKind = deadlineKind
        self.windowDuration = windowDuration
        self.group = group
        self.value = value
        self.showsProgress = showsProgress
        self.allowsLimitEditing = allowsLimitEditing
    }

    var clampedPercent: Double { min(max(usedPercent, 0), 100) }
    var remainingPercent: Double { min(max(100 - usedPercent, 0), 100) }

    func deadlineDescription(at date: Date = Date()) -> String? {
        guard let deadlineAt else { return nil }
        let interval = deadlineAt.timeIntervalSince(date)
        let action = deadlineKind == .expiration ? "到期" : "重置"
        if interval <= 0 { return "即将\(action)" }
        let hours = Int(interval / 3_600)
        if hours < 24 { return "\(max(hours, 1)) 小时后\(action)" }
        let days = Int(ceil(interval / 86_400))
        return "\(days) 天后\(action)"
    }

    func suggestedUsedPercent(at date: Date = Date()) -> Double? {
        guard let deadlineAt, let windowDuration, windowDuration > 0 else { return nil }
        let remaining = deadlineAt.timeIntervalSince(date)
        if remaining > windowDuration { return 0 }
        if remaining <= 0 { return 100 }

        let pacingUnit: TimeInterval = windowDuration >= 24 * 60 * 60
            ? 24 * 60 * 60
            : 60 * 60
        let totalUnits = max(1, Int(round(windowDuration / pacingUnit)))
        let elapsed = windowDuration - remaining
        let currentUnit = min(totalUnits, Int(floor(elapsed / pacingUnit)) + 1)
        return Double(currentUnit) / Double(totalUnits) * 100
    }
}

struct ProviderSnapshot: Equatable, Sendable {
    let provider: ProviderKind
    let planName: String?
    let metrics: [UsageMetric]
    let fetchedAt: Date
    let note: String?
    let subscriptionCategory: SubscriptionCategory

    init(
        provider: ProviderKind,
        planName: String?,
        metrics: [UsageMetric],
        fetchedAt: Date,
        note: String?,
        subscriptionCategory: SubscriptionCategory = .unknown
    ) {
        self.provider = provider
        self.planName = planName
        self.metrics = metrics
        self.fetchedAt = fetchedAt
        self.note = note
        self.subscriptionCategory = subscriptionCategory
    }

    var primaryMetric: UsageMetric? {
        if provider == .cursor,
           let personalOnDemand = metrics.first(where: {
               $0.id == "on_demand_personal" && $0.showsProgress
           }) {
            return personalOnDemand
        }
        return metrics.first(where: \.showsProgress)
    }
}

struct ProviderDisplayState: Equatable, Sendable {
    var snapshot: ProviderSnapshot?
    var errorMessage: String?
    var isStale = false
    var requiresSignIn = false
}

enum UsageError: LocalizedError, Sendable {
    case notInstalled(String)
    case notSignedIn(String)
    case timedOut(String)
    case invalidResponse(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let message), .notSignedIn(let message),
             .timedOut(let message), .invalidResponse(let message),
             .requestFailed(let message):
            return message
        }
    }

    var requiresSignIn: Bool {
        if case .notSignedIn = self { return true }
        return false
    }
}

enum DateParsing {
    static func date(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        guard let string = value as? String else { return nil }
        if let number = Double(string) {
            return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}

extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }

    func double(_ key: String) -> Double? {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let string = self[key] as? String { return Double(string) }
        return nil
    }
}
