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
    @Published private(set) var archivedProviders: Set<ProviderKind>
    @Published private(set) var menuBarProviders: Set<ProviderKind>
    @Published private(set) var cursorIndividualLimitCents: Int64?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var simulationCategory: SubscriptionCategory?
    @Published private(set) var isCloudSyncEnabled: Bool
    @Published private(set) var cloudSyncStatus: CloudSyncStatus

    private let defaults: UserDefaults
    private let codex = CodexProvider()
    private let cursor = CursorProvider()
    private let claude = ClaudeCodeProvider()
    private let kiro = KiroProvider()
    private let qoder = QoderProvider()
    private let cloudSync = CloudUsageSyncService()
    private var refreshLoop: Task<Void, Never>?
    private var cloudSyncTask: Task<Void, Never>?
    private var refreshAfterCurrent = false
    private let cursorIndividualLimitKey = "cursor.onDemand.personalLimitCents.v1"
    private let archivedProvidersKey = "providers.archived.v1"
    private let cloudSyncEnabledKey = "icloud.sync.enabled.v1"

    init(
        defaults: UserDefaults = .standard,
        simulationCategory: SubscriptionCategory? = SubscriptionSimulation.launchCategory()
    ) {
        self.defaults = defaults
        self.simulationCategory = simulationCategory
        let cloudSyncEnabled = simulationCategory == nil
            && defaults.bool(forKey: "icloud.sync.enabled.v1")
        self.isCloudSyncEnabled = cloudSyncEnabled
        self.cloudSyncStatus = cloudSyncEnabled ? .idle : .disabled
        self.archivedProviders = ProviderArchive.decode(
            defaults.stringArray(forKey: "providers.archived.v1") ?? []
        )
        if let simulationCategory {
            self.cursorIndividualLimitCents = nil
            self.menuBarProviders = Set(ProviderKind.allCases)
            self.installedProviders = ProviderKind.allCases
            self.archivedProviders = []
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
        let providersToRefresh = displayedProviders
        let cursorLimit = cursorIndividualLimitCents

        var tasks: [Task<CapturedResult, Never>] = []
        if providersToRefresh.contains(.codex) {
            tasks.append(Task {
                await self.capture(provider: .codex) { try await self.codex.fetch() }
            })
        }
        if providersToRefresh.contains(.cursor) {
            tasks.append(Task {
                await self.capture(provider: .cursor) {
                    try await self.cursor.fetch(individualLimitCents: cursorLimit)
                }
            })
        }
        if providersToRefresh.contains(.claude) {
            tasks.append(Task {
                await self.capture(provider: .claude) { try await self.claude.fetch() }
            })
        }
        if providersToRefresh.contains(.kiro) {
            tasks.append(Task {
                await self.capture(provider: .kiro) { try await self.kiro.fetch() }
            })
        }
        if providersToRefresh.contains(.qoder) {
            tasks.append(Task {
                await self.capture(provider: .qoder) { try await self.qoder.fetch() }
            })
        }

        var successfulSnapshots: [ProviderSnapshot] = []
        for task in tasks {
            let result = await task.value
            switch result {
            case .success(let snapshot):
                states[snapshot.provider] = ProviderDisplayState(snapshot: snapshot)
                successfulSnapshots.append(snapshot)
            case .failure(let failure):
                var state = states[failure.provider] ?? ProviderDisplayState()
                state.errorMessage = failure.message
                state.isStale = state.snapshot != nil
                state.requiresSignIn = failure.requiresSignIn
                states[failure.provider] = state
            }
        }
        lastUpdated = Date()
        isRefreshing = false
        scheduleCloudSync(successfulSnapshots)
        if refreshAfterCurrent {
            refreshAfterCurrent = false
            await refresh()
        }
    }

    func state(for provider: ProviderKind) -> ProviderDisplayState {
        states[provider] ?? ProviderDisplayState()
    }

    var displayedProviders: [ProviderKind] {
        ProviderKind.allCases.filter {
            installedProviders.contains($0) && !archivedProviders.contains($0)
        }
    }

    var archivedProvidersList: [ProviderKind] {
        ProviderKind.allCases.filter(archivedProviders.contains)
    }

    var visibleMenuBarProviders: [ProviderKind] {
        ProviderKind.allCases.filter {
            installedProviders.contains($0)
                && !archivedProviders.contains($0)
                && menuBarProviders.contains($0)
        }
    }

    func archive(_ provider: ProviderKind) {
        guard installedProviders.contains(provider), !archivedProviders.contains(provider)
        else { return }
        var updated = archivedProviders
        updated.insert(provider)
        setArchivedProviders(updated)
    }

    func unarchive(_ provider: ProviderKind) {
        guard archivedProviders.contains(provider) else { return }
        var updated = archivedProviders
        updated.remove(provider)
        setArchivedProviders(updated)
        guard simulationCategory == nil, installedProviders.contains(provider) else { return }
        if isRefreshing {
            refreshAfterCurrent = true
        } else {
            Task { await refresh() }
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

    func setCloudSyncEnabled(_ enabled: Bool) {
        guard simulationCategory == nil, enabled != isCloudSyncEnabled else { return }
        isCloudSyncEnabled = enabled
        defaults.set(enabled, forKey: cloudSyncEnabledKey)
        cloudSyncTask?.cancel()
        if enabled {
            cloudSyncStatus = .idle
            scheduleCloudSync(states.values.compactMap(\.snapshot))
        } else {
            cloudSyncStatus = .disabled
        }
    }

    var cursorIndividualLimitDollars: Double? {
        cursorIndividualLimitCents.map { Double($0) / 100 }
    }

    private func setArchivedProviders(_ providers: Set<ProviderKind>) {
        archivedProviders = providers
        guard simulationCategory == nil else { return }
        defaults.set(ProviderArchive.encode(providers), forKey: archivedProvidersKey)
    }

    private func scheduleCloudSync(_ snapshots: [ProviderSnapshot]) {
        guard isCloudSyncEnabled, !snapshots.isEmpty else { return }
        let payloads = snapshots.map(CloudUsageSnapshot.init)
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            guard let self else { return }
            self.cloudSyncStatus = .syncing
            do {
                try await self.cloudSync.save(payloads)
                guard !Task.isCancelled else { return }
                self.cloudSyncStatus = .synced(Date())
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.cloudSyncStatus = .unavailable(
                    (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                )
            }
        }
    }

    func menuBarText(for providers: [ProviderKind]) -> String {
        providers.map { provider in
            let snapshot = state(for: provider).snapshot
            guard let metric = snapshot?.primaryMetric else {
                return isRefreshing
                    ? L10n.format("menu.updating", provider.title)
                    : L10n.format("menu.no_data", provider.title)
            }
            if provider == .cursor, metric.id == "on_demand_personal" {
                let key = snapshot?.subscriptionCategory.hasSharedOrganizationContext == true
                    ? (metric.allowsLimitEditing
                        ? "menu.cursor.personal_budget_remaining"
                        : "menu.cursor.personal_limit_remaining")
                    : (metric.allowsLimitEditing
                        ? "menu.cursor.budget_remaining"
                        : "menu.cursor.limit_remaining")
                return L10n.format(key, Int(metric.remainingPercent.rounded()))
            }
            if provider == .cursor {
                return L10n.format(
                    "menu.cursor.included_remaining",
                    Int(metric.remainingPercent.rounded())
                )
            }
            return L10n.format(
                "menu.provider_remaining",
                provider.title,
                Int(metric.remainingPercent.rounded())
            )
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
        let requiresSignIn: Bool
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
            let usageError = error as? UsageError
            return .failure(CapturedFailure(
                provider: provider,
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                requiresSignIn: usageError?.requiresSignIn ?? false
            ))
        }
    }
}
