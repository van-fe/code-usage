import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [ProviderKind: ProviderDisplayState] = [
        .codex: ProviderDisplayState(),
        .cursor: ProviderDisplayState(),
        .claude: ProviderDisplayState(),
        .kiro: ProviderDisplayState(),
        .qoder: ProviderDisplayState()
    ]
    @Published private(set) var installedProviders = ProviderInstallation.installedProviders()
    @Published private(set) var menuBarProviders: Set<ProviderKind>
    @Published private(set) var cursorIndividualLimitCents: Int64?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var simulationCategory: SubscriptionCategory?

    private let defaults: UserDefaults
    private let codex = CodexProvider()
    private let cursor = CursorProvider()
    private let claude = ClaudeCodeProvider()
    private let kiro = KiroProvider()
    private let qoder = QoderProvider()
    private var refreshLoop: Task<Void, Never>?
    private var refreshAfterCurrent = false
    private let cursorIndividualLimitKey = "cursor.onDemand.personalLimitCents.v1"

    init(
        defaults: UserDefaults = .standard,
        simulationCategory: SubscriptionCategory? = SubscriptionSimulation.launchCategory()
    ) {
        self.defaults = defaults
        self.simulationCategory = simulationCategory
        if let simulationCategory {
            self.cursorIndividualLimitCents = nil
            self.menuBarProviders = Set(ProviderKind.allCases)
            self.installedProviders = ProviderKind.allCases
            self.states = SubscriptionSimulation.states(for: simulationCategory)
            self.lastUpdated = Date()
            return
        }
        if let stored = defaults.object(
            forKey: "cursor.onDemand.personalLimitCents.v1"
        ) as? NSNumber, stored.int64Value > 0 {
            self.cursorIndividualLimitCents = stored.int64Value
        } else if let legacy = defaults.object(
            forKey: "cursor.onDemandIndividualLimitDollars"
        ) as? NSNumber, legacy.doubleValue.isFinite, legacy.doubleValue > 0 {
            let cents = Int64((legacy.doubleValue * 100).rounded())
            self.cursorIndividualLimitCents = cents
            defaults.set(cents, forKey: "cursor.onDemand.personalLimitCents.v1")
            defaults.removeObject(forKey: "cursor.onDemandIndividualLimitDollars")
        } else {
            self.cursorIndividualLimitCents = nil
        }
        self.menuBarProviders = Set(ProviderKind.allCases.filter { provider in
            defaults.object(forKey: provider.menuBarPreferenceKey) == nil
                || defaults.bool(forKey: provider.menuBarPreferenceKey)
        })
    }

    func start() {
        guard simulationCategory == nil else { return }
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        if let simulationCategory {
            states = SubscriptionSimulation.states(for: simulationCategory)
            installedProviders = ProviderKind.allCases
            lastUpdated = Date()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        installedProviders = ProviderInstallation.installedProviders()
        let cursorLimit = cursorIndividualLimitCents

        var tasks: [Task<CapturedResult, Never>] = []
        if installedProviders.contains(.codex) {
            tasks.append(Task {
                await self.capture(provider: .codex) { try await self.codex.fetch() }
            })
        }
        if installedProviders.contains(.cursor) {
            tasks.append(Task {
                await self.capture(provider: .cursor) {
                    try await self.cursor.fetch(individualLimitCents: cursorLimit)
                }
            })
        }
        if installedProviders.contains(.claude) {
            tasks.append(Task {
                await self.capture(provider: .claude) { try await self.claude.fetch() }
            })
        }
        if installedProviders.contains(.kiro) {
            tasks.append(Task {
                await self.capture(provider: .kiro) { try await self.kiro.fetch() }
            })
        }
        if installedProviders.contains(.qoder) {
            tasks.append(Task {
                await self.capture(provider: .qoder) { try await self.qoder.fetch() }
            })
        }

        for task in tasks {
            let result = await task.value
            switch result {
            case .success(let snapshot):
                states[snapshot.provider] = ProviderDisplayState(snapshot: snapshot)
            case .failure(let failure):
                var state = states[failure.provider] ?? ProviderDisplayState()
                state.errorMessage = failure.message
                state.isStale = state.snapshot != nil
                states[failure.provider] = state
            }
        }
        lastUpdated = Date()
        isRefreshing = false
        if refreshAfterCurrent {
            refreshAfterCurrent = false
            await refresh()
        }
    }

    func state(for provider: ProviderKind) -> ProviderDisplayState {
        states[provider] ?? ProviderDisplayState()
    }

    var visibleMenuBarProviders: [ProviderKind] {
        ProviderKind.allCases.filter {
            installedProviders.contains($0) && menuBarProviders.contains($0)
        }
    }

    func isShownInMenuBar(_ provider: ProviderKind) -> Bool {
        menuBarProviders.contains(provider)
    }

    func toggleMenuBarVisibility(_ provider: ProviderKind) {
        var updated = menuBarProviders
        if updated.contains(provider) {
            updated.remove(provider)
        } else {
            updated.insert(provider)
        }
        menuBarProviders = updated
        if simulationCategory == nil {
            defaults.set(updated.contains(provider), forKey: provider.menuBarPreferenceKey)
        }
    }

    var isSimulationMode: Bool {
        simulationCategory != nil
    }

    func setSimulationCategory(_ category: SubscriptionCategory) {
        guard simulationCategory != nil, category != .unknown else { return }
        simulationCategory = category
        states = SubscriptionSimulation.states(for: category)
        installedProviders = ProviderKind.allCases
        lastUpdated = Date()
    }

    func setCursorIndividualLimitDollars(_ value: Double?) {
        guard simulationCategory == nil else { return }
        let normalized: Int64? = value.flatMap {
            guard $0.isFinite, $0 > 0,
                  $0 <= Double(Int64.max) / 100 else { return nil }
            return Int64(($0 * 100).rounded())
        }.flatMap { $0 > 0 ? $0 : nil }
        guard normalized != cursorIndividualLimitCents else { return }
        cursorIndividualLimitCents = normalized
        if let normalized {
            defaults.set(normalized, forKey: cursorIndividualLimitKey)
        } else {
            defaults.removeObject(forKey: cursorIndividualLimitKey)
        }

        if isRefreshing {
            refreshAfterCurrent = true
        } else {
            Task { await refresh() }
        }
    }

    var cursorIndividualLimitDollars: Double? {
        cursorIndividualLimitCents.map { Double($0) / 100 }
    }

    func menuBarText(for providers: [ProviderKind]) -> String {
        providers.map { provider in
            let snapshot = state(for: provider).snapshot
            guard let metric = snapshot?.primaryMetric else {
                return isRefreshing
                    ? "\(provider.title) 正在更新…"
                    : "\(provider.title) 暂无数据"
            }
            if provider == .cursor, metric.id == "on_demand_personal" {
                let owner = snapshot?.subscriptionCategory.hasSharedOrganizationContext == true
                    ? "我的"
                    : ""
                let basis = metric.allowsLimitEditing ? "显示预算" : "额度"
                return "Cursor \(owner)按量付费\(basis)剩余 \(Int(metric.remainingPercent.rounded()))%"
            }
            if provider == .cursor {
                return "Cursor 套餐额度剩余 \(Int(metric.remainingPercent.rounded()))%"
            }
            return "\(provider.title) 剩余 \(Int(metric.remainingPercent.rounded()))%"
        }.joined(separator: " · ")
    }

    func remainingText(for provider: ProviderKind) -> String {
        let state = state(for: provider)
        if let metric = state.snapshot?.primaryMetric {
            return "\(Int(metric.remainingPercent.rounded()))%"
        }
        return isRefreshing ? "…" : "–"
    }

    private struct CapturedFailure: Sendable {
        let provider: ProviderKind
        let message: String
    }

    private enum CapturedResult: Sendable {
        case success(ProviderSnapshot)
        case failure(CapturedFailure)
    }

    private func capture(
        provider: ProviderKind,
        _ operation: @escaping @Sendable () async throws -> ProviderSnapshot
    ) async -> CapturedResult {
        do {
            return .success(try await operation())
        } catch {
            return .failure(CapturedFailure(
                provider: provider,
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ))
        }
    }
}
