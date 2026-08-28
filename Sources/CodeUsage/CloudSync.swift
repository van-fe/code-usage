import CloudKit
import Foundation
import Security

struct CloudUsageMetric: Codable, Equatable, Sendable {
    enum Value: Codable, Equatable, Sendable {
        case usd(usedCents: Int64, limitCents: Int64?)
        case quantity(used: Double?, limit: Double?, remaining: Double?, unit: String)
    }

    let id: String
    let title: String
    let usedPercent: Double
    let deadlineAt: Date?
    let deadlineKind: String
    let windowDuration: TimeInterval?
    let group: String?
    let value: Value?
    let showsProgress: Bool
    let allowsLimitEditing: Bool

    init(metric: UsageMetric) {
        id = metric.id
        title = metric.title
        usedPercent = metric.usedPercent
        deadlineAt = metric.deadlineAt
        deadlineKind = metric.deadlineKind == .expiration ? "expiration" : "reset"
        windowDuration = metric.windowDuration
        group = metric.group?.rawValue
        switch metric.value {
        case .usd(let usedCents, let limitCents):
            value = .usd(usedCents: usedCents, limitCents: limitCents)
        case .quantity(let used, let limit, let remaining, let unit):
            value = .quantity(used: used, limit: limit, remaining: remaining, unit: unit)
        case nil:
            value = nil
        }
        showsProgress = metric.showsProgress
        allowsLimitEditing = metric.allowsLimitEditing
    }
}

/// The complete payload shared with the user's private CloudKit database.
/// Keep this model limited to derived display data. Authentication material,
/// local file paths, raw command output, and provider response bodies must
/// never be added here.
struct CloudUsageSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let provider: String
    let planName: String?
    let subscriptionCategory: String
    let metrics: [CloudUsageMetric]
    let fetchedAt: Date

    init(snapshot: ProviderSnapshot) {
        schemaVersion = Self.schemaVersion
        provider = snapshot.provider.rawValue
        planName = snapshot.planName
        subscriptionCategory = snapshot.subscriptionCategory.rawValue
        metrics = snapshot.metrics.map(CloudUsageMetric.init)
        fetchedAt = snapshot.fetchedAt
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

enum CloudSyncStatus: Equatable, Sendable {
    case disabled
    case idle
    case syncing
    case synced(Date)
    case unavailable(String)
}

enum CloudSyncError: LocalizedError {
    case missingEntitlement
    case accountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .missingEntitlement:
            return "当前 App 未包含 iCloud 签名权限，请安装正式签名版本。"
        case .accountUnavailable(let status):
            switch status {
            case .noAccount:
                return "这台 Mac 尚未登录 iCloud。"
            case .restricted:
                return "当前 iCloud 账号受到系统限制。"
            case .temporarilyUnavailable:
                return "iCloud 暂时不可用，请稍后重试。"
            case .couldNotDetermine, .available:
                return "暂时无法确认 iCloud 账号状态。"
            @unknown default:
                return "当前 iCloud 账号不可用。"
            }
        }
    }
}

actor CloudUsageSyncService {
    static let containerIdentifier = "iCloud.com.van-fe.CodeUsage"
    static let recordType = "UsageSnapshot"

    func save(_ snapshots: [CloudUsageSnapshot]) async throws {
        guard !snapshots.isEmpty else { return }
        guard Self.hasRequiredEntitlement() else {
            throw CloudSyncError.missingEntitlement
        }

        let container = CKContainer(identifier: Self.containerIdentifier)
        let accountStatus = try await accountStatus(for: container)
        guard accountStatus == .available else {
            throw CloudSyncError.accountUnavailable(accountStatus)
        }

        let database = container.privateCloudDatabase
        for snapshot in snapshots {
            try Task.checkCancellation()
            let recordID = CKRecord.ID(recordName: "usage-\(snapshot.provider)")
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: Self.recordType, recordID: recordID)
            }
            record["provider"] = snapshot.provider as CKRecordValue
            record["schemaVersion"] = snapshot.schemaVersion as CKRecordValue
            record["updatedAt"] = snapshot.fetchedAt as CKRecordValue
            record["payload"] = try snapshot.encoded() as CKRecordValue
            _ = try await database.save(record)
        }
    }

    private func accountStatus(for container: CKContainer) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private static func hasRequiredEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.icloud-container-identifiers" as CFString,
                  nil
              ) as? [String]
        else { return false }
        return value.contains(containerIdentifier)
    }
}
