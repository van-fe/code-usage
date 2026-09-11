import Foundation

public struct SharedUsageMetric: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let groupTitle: String?
    public let usedPercent: Double?
    public let remainingPercent: Int?
    public let deadlineText: String?
    public let valueText: String?
    public let suggestedUsedPercent: Double?
    public let showsProgress: Bool
    public let isPrimary: Bool

    public init(
        id: String,
        title: String,
        groupTitle: String?,
        usedPercent: Double?,
        remainingPercent: Int?,
        deadlineText: String?,
        valueText: String?,
        suggestedUsedPercent: Double?,
        showsProgress: Bool,
        isPrimary: Bool
    ) {
        self.id = id
        self.title = title
        self.groupTitle = groupTitle
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.deadlineText = deadlineText
        self.valueText = valueText
        self.suggestedUsedPercent = suggestedUsedPercent
        self.showsProgress = showsProgress
        self.isPrimary = isPrimary
    }
}

public struct SharedUsageProvider: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let planName: String?
    public let metricTitle: String?
    public let remainingPercent: Int?
    public let isStale: Bool
    public let metrics: [SharedUsageMetric]?
    public let errorMessage: String?

    public init(
        id: String,
        title: String,
        planName: String?,
        metricTitle: String?,
        remainingPercent: Int?,
        isStale: Bool,
        metrics: [SharedUsageMetric]? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.planName = planName
        self.metricTitle = metricTitle
        self.remainingPercent = remainingPercent
        self.isStale = isStale
        self.metrics = metrics
        self.errorMessage = errorMessage
    }

    public var displayMetrics: [SharedUsageMetric] {
        if let metrics, !metrics.isEmpty { return metrics }
        if let errorMessage, !errorMessage.isEmpty {
            return [SharedUsageMetric(
                id: "status",
                title: errorMessage,
                groupTitle: nil,
                usedPercent: nil,
                remainingPercent: nil,
                deadlineText: nil,
                valueText: nil,
                suggestedUsedPercent: nil,
                showsProgress: false,
                isPrimary: true
            )]
        }
        guard metricTitle != nil || remainingPercent != nil else { return [] }
        return [SharedUsageMetric(
            id: "primary",
            title: metricTitle ?? planName ?? "",
            groupTitle: nil,
            usedPercent: remainingPercent.map { Double(100 - $0) },
            remainingPercent: remainingPercent,
            deadlineText: nil,
            valueText: nil,
            suggestedUsedPercent: nil,
            showsProgress: remainingPercent != nil,
            isPrimary: true
        )]
    }

    public var primaryMetric: SharedUsageMetric? {
        displayMetrics.first(where: \.isPrimary) ?? displayMetrics.first
    }
}

public struct SharedUsageSnapshot: Codable, Equatable, Sendable {
    public let providers: [SharedUsageProvider]
    public let updatedAt: Date?
    public let isRefreshing: Bool

    public init(
        providers: [SharedUsageProvider],
        updatedAt: Date?,
        isRefreshing: Bool
    ) {
        self.providers = providers
        self.updatedAt = updatedAt
        self.isRefreshing = isRefreshing
    }

    public static let empty = SharedUsageSnapshot(
        providers: [],
        updatedAt: nil,
        isRefreshing: false
    )

    public var lowestRemainingPercent: Int? {
        providers.compactMap(\.remainingPercent).min()
    }
}

public enum SharedUsageSnapshotStore {
    public static let appGroupIdentifier = "group.com.van-fe.CodeUsage.shared"
    public static let widgetKindPrefix = "com.van-fe.CodeUsage.usage"

    private static let fileName = "widget-snapshot-v1.json"
    private static let localFallbackInfoKey = "CodeUsageLocalWidgetSnapshot"

    private enum StoreError: LocalizedError {
        case sharedContainerUnavailable

        var errorDescription: String? {
            "CodeUsage widget shared storage is unavailable."
        }
    }

    public static func read() -> SharedUsageSnapshot {
        let decoder = JSONDecoder()
        for url in readableSnapshotURLs {
            if let data = try? Data(contentsOf: url),
               let snapshot = try? decoder.decode(SharedUsageSnapshot.self, from: data) {
                return snapshot
            }
        }
        return .empty
    }

    public static func write(_ snapshot: SharedUsageSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard !writableSnapshotURLs.isEmpty else {
            throw StoreError.sharedContainerUnavailable
        }
        var lastError: Error?
        var didWrite = false
        for url in writableSnapshotURLs {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                didWrite = true
            } catch {
                lastError = error
            }
        }
        if !didWrite, let lastError { throw lastError }
    }

    private static var groupContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    private static func applicationSupportSnapshotURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("CodeUsage", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static var localFallbackEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: localFallbackInfoKey) as? NSNumber)?
            .boolValue == true
    }

    private static var readableSnapshotURLs: [URL] {
        resolvedReadableSnapshotURLs(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            userAccountHomeDirectory: FileManager.default.homeDirectory(
                forUser: NSUserName()
            ),
            groupContainerURL: groupContainerURL,
            localFallbackEnabled: localFallbackEnabled
        )
    }

    static func resolvedReadableSnapshotURLs(
        homeDirectory: URL,
        userAccountHomeDirectory: URL?,
        groupContainerURL: URL?,
        localFallbackEnabled: Bool
    ) -> [URL] {
        var urls: [URL] = []
        func appendUnique(_ url: URL) {
            guard !urls.contains(url) else { return }
            urls.append(url)
        }
        if let groupContainerURL {
            appendUnique(groupContainerURL.appendingPathComponent(fileName))
        }
        if localFallbackEnabled {
            appendUnique(applicationSupportSnapshotURL(homeDirectory: homeDirectory))
            if let userAccountHomeDirectory {
                appendUnique(applicationSupportSnapshotURL(
                    homeDirectory: userAccountHomeDirectory
                ))
            }
        }
        return urls
    }

    private static var writableSnapshotURLs: [URL] {
        resolvedWritableSnapshotURLs(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            groupContainerURL: groupContainerURL,
            hostBundleIdentifier: Bundle.main.bundleIdentifier,
            localFallbackEnabled: localFallbackEnabled
        )
    }

    static func resolvedWritableSnapshotURLs(
        homeDirectory: URL,
        groupContainerURL: URL?,
        hostBundleIdentifier: String?,
        localFallbackEnabled: Bool
    ) -> [URL] {
        var urls: [URL] = []
        if let groupContainerURL {
            urls.append(groupContainerURL.appendingPathComponent(fileName))
        }
        if localFallbackEnabled {
            urls.append(applicationSupportSnapshotURL(homeDirectory: homeDirectory))
            if let localWidgetContainerSnapshotURL = localWidgetContainerSnapshotURL(
                homeDirectory: homeDirectory,
                hostBundleIdentifier: hostBundleIdentifier
            ) {
                // An ad-hoc extension cannot use an App Group. Local packages
                // explicitly opt into this mirror; signed releases never do.
                urls.append(localWidgetContainerSnapshotURL)
            }
        }
        return urls
    }

    static func localWidgetContainerSnapshotURL(
        homeDirectory: URL,
        hostBundleIdentifier: String?
    ) -> URL? {
        guard let hostBundleIdentifier,
              !hostBundleIdentifier.isEmpty,
              !hostBundleIdentifier.hasSuffix(".widgets") else { return nil }
        return homeDirectory
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent("\(hostBundleIdentifier).widgets", isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent("CodeUsage", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
