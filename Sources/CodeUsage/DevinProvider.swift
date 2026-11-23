import CoreFoundation
import Foundation
import SQLite3

actor DevinProvider {
    private let http = ProviderHTTPClient()
    static var databasePath: String {
        ProcessUtils.expandedHome("~/Library/Application Support/Devin/User/globalStorage/state.vscdb")
    }

    func fetch() async throws -> ProviderSnapshot {
        let key = try Self.readAPIKey()
        let packagePath = "/Applications/Devin.app/Contents/Resources/app/package.json"
        let package = (try? Data(contentsOf: URL(fileURLWithPath: packagePath)))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let version = package?["version"] as? String ?? "1.0"
        let request = try Self.request(apiKey: key, version: version)
        return try Self.map(data: await http.read(request, provider: .devin))
    }

    private static func readAPIKey() throws -> String {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw UsageError.notSignedIn("未找到 Devin 客户端登录数据，请先安装并登录 Devin")
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw UsageError.requestFailed("无法读取 Devin 客户端登录状态")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        // Select only the token, never the large model/configuration payload.
        let query = "SELECT json_extract(value, '$.apiKey'), json_extract(value, '$.apiServerUrl') FROM ItemTable WHERE key = 'windsurfAuthStatus'"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.invalidResponse("Devin 客户端登录数据格式无效")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else {
            throw UsageError.notSignedIn("请在 Devin 客户端登录后刷新")
        }
        if let server = sqlite3_column_text(statement, 1), String(cString: server) != "https://server.codeium.com" {
            throw UsageError.requestFailed("暂不支持此 Devin 客户端服务地址")
        }
        return String(cString: raw)
    }

    static func request(apiKey: String, version: String) throws -> URLRequest {
        guard !apiKey.isEmpty, apiKey.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw UsageError.notSignedIn("请在 Devin 客户端登录后刷新")
        }
        var request = URLRequest(url: URL(string: "https://server.codeium.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        // Devin Desktop retains these protocol identifiers from Windsurf.
        request.httpBody = try JSONSerialization.data(withJSONObject: ["metadata": [
            "apiKey": apiKey, "ideName": "windsurf", "extensionName": "windsurf",
            "ideVersion": version, "extensionVersion": version, "locale": "en", "os": "macos",
            "sessionId": UUID().uuidString
        ]])
        return request
    }

    static func map(data: Data, now: Date = Date()) throws -> ProviderSnapshot {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = response.dictionary("userStatus"), let plan = user.dictionary("planStatus"),
              let info = plan.dictionary("planInfo") else { throw invalidResponse }
        let name = info["planName"] as? String
        let category: SubscriptionCategory = info["isEnterprise"] as? Bool == true ? .enterprise
            : info["isTeams"] as? Bool == true ? .team : .inferred(from: name)
        let strategy = try billingStrategy(info["billingStrategy"])
        let start = try timestamp(plan["planStart"])
        let end = try timestamp(plan["planEnd"])
        let window = start.flatMap { start in end.flatMap { $0 > start ? $0.timeIntervalSince(start) : nil } }
        var metrics: [UsageMetric] = []

        for (id, title, remainingKey, resetKey, hiddenKey) in [
            ("daily", "日额度", "dailyQuotaRemainingPercent", "dailyQuotaResetAtUnix", "hideDailyQuota"),
            ("weekly", "周额度", "weeklyQuotaRemainingPercent", "weeklyQuotaResetAtUnix", "hideWeeklyQuota")
        ] {
            guard info[hiddenKey] as? Bool != true else { continue }
            let remaining = try number(plan, remainingKey)
            let reset = try number(plan, resetKey)
            // Known quota plans use proto3 scalar defaults. A missing reset
            // does not make a reported percentage disappear or invent a date.
            guard reset == nil || (0...253402300799).contains(reset!) else { throw invalidResponse }
            guard strategy == .quota || remaining != nil || (reset ?? 0) > 0 else { continue }
            let value = remaining ?? 0
            guard (0...100).contains(value) else { throw invalidResponse }
            metrics.append(UsageMetric(id: id, title: title, usedPercent: 100 - value,
                                       deadlineAt: reset.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }))
        }

        for (id, title, usedKey, limitKey, unit) in [
            ("acu", "套餐 ACU", "acuConsumed", "acuLimit", "ACU"),
            ("dollars", "美元用量", "dollarsConsumed", "dollarsLimit", "USD")
        ] {
            let used = try number(plan, usedKey)
            let reportedLimit = try number(plan, limitKey)
            guard used != nil || reportedLimit != nil else { continue }
            guard used == nil || used! >= 0,
                  reportedLimit == nil || reportedLimit! >= 0 || reportedLimit == -1 else { throw invalidResponse }
            let limit = reportedLimit == -1 ? nil : reportedLimit
            let progress = used != nil && (limit ?? 0) > 0
            metrics.append(UsageMetric(id: id, title: reportedLimit == -1 ? title + "（不限量）" : title,
                usedPercent: progress ? try percentage(used!, limit!) : 0, deadlineAt: end, windowDuration: window,
                value: .quantity(used: used, limit: limit, remaining: nil, unit: unit), showsProgress: progress))
        }

        // Credits are stored in hundredths in the desktop protocol. Do not
        // interpret leftover zero credit fields on QUOTA/ACU plans as a second
        // allowance. The add-on pool has no monthly reset.
        let creditKeys = ["availablePromptCredits", "usedPromptCredits", "availableFlowCredits", "usedFlowCredits", "availableFlexCredits", "usedFlexCredits"]
        let hasCredits = creditKeys.contains { plan[$0] != nil }
        if strategy == .credits || (strategy == .unspecified && metrics.isEmpty && hasCredits) {
            for (id, title, limitKey, usedKey, resets) in [
                ("prompt_credits", "Prompt Credits", "availablePromptCredits", "usedPromptCredits", true),
                ("flow_credits", "Flow Credits", "availableFlowCredits", "usedFlowCredits", true),
                ("add_on_credits", "加购 Credits", "availableFlexCredits", "usedFlexCredits", false)
            ] {
                guard plan[limitKey] != nil || plan[usedKey] != nil else { continue }
                let used = try number(plan, usedKey) ?? 0
                let reportedLimit = try number(plan, limitKey) ?? 0
                guard used >= 0, reportedLimit >= 0 || reportedLimit == -1 else { throw invalidResponse }
                let limit = reportedLimit == -1 ? nil : reportedLimit / 100
                let progress = (limit ?? 0) > 0
                metrics.append(UsageMetric(id: id, title: reportedLimit == -1 ? title + "（不限量）" : title,
                    usedPercent: progress ? try percentage(used / 100, limit!) : 0,
                    deadlineAt: resets ? end : nil, windowDuration: resets ? window : nil,
                    group: resets ? nil : (category.hasSharedOrganizationContext ? .organizationShared : .personalAddOn),
                    value: .quantity(used: used / 100, limit: limit,
                        remaining: limit.map { max(0, $0 - used / 100) }, unit: "Credits"), showsProgress: progress))
            }
        }

        let micros = try number(plan, "overageBalanceMicros")
        if let micros = micros ?? (strategy == .quota ? 0 : nil) {
            // This is prepaid money, not a percentage or a credit count.
            metrics.append(UsageMetric(id: "overage_balance", title: category.hasSharedOrganizationContext ? "共享按量余额" : "额外消费余额",
                usedPercent: 0, deadlineAt: nil,
                group: category.hasSharedOrganizationContext ? .organizationShared : .onDemand,
                value: .quantity(used: nil, limit: nil, remaining: micros / 1_000_000, unit: "USD"), showsProgress: false))
        }
        return ProviderSnapshot(provider: .devin, planName: name, metrics: metrics, fetchedAt: now,
            note: metrics.isEmpty ? "当前套餐未返回可显示的用量，请在 Devin 客户端查看。" : nil,
            subscriptionCategory: category)
    }

    private enum BillingStrategy { case unspecified, credits, quota, acu }

    private static func billingStrategy(_ value: Any?) throws -> BillingStrategy {
        guard let value else { return .unspecified }
        if let text = value as? String {
            switch text {
            case "BILLING_STRATEGY_UNSPECIFIED", "UNSPECIFIED", "0": return .unspecified
            case "BILLING_STRATEGY_CREDITS", "CREDITS", "1": return .credits
            case "BILLING_STRATEGY_QUOTA", "QUOTA", "2": return .quota
            case "BILLING_STRATEGY_ACU", "ACU", "3": return .acu
            default: throw invalidResponse
            }
        }
        guard let raw = try number(["value": value], "value") else { return .unspecified }
        switch raw {
        case 0: return .unspecified
        case 1: return .credits
        case 2: return .quota
        case 3: return .acu
        default: throw invalidResponse
        }
    }

    private static func percentage(_ used: Double, _ limit: Double) throws -> Double {
        let result = used / limit * 100
        guard result.isFinite else { throw invalidResponse }
        return result
    }

    private static func number(_ object: [String: Any], _ key: String) throws -> Double? {
        guard let value = object[key] else { return nil }
        // JSON booleans bridge to NSNumber too; they are never usage amounts.
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { throw invalidResponse }
        let parsed: Double?
        if let value = value as? NSNumber { parsed = value.doubleValue }
        else if let value = value as? String { parsed = Double(value) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite else { throw invalidResponse }
        return parsed
    }

    private static func timestamp(_ value: Any?) throws -> Date? {
        guard let value else { return nil }
        if let object = value as? [String: Any], let seconds = try number(object, "seconds") {
            guard (0...253402300799).contains(seconds) else { throw invalidResponse }
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        if let value = value as? String, let date = DateParsing.date(from: value), date.timeIntervalSince1970.isFinite {
            guard (0...253402300799).contains(date.timeIntervalSince1970) else { throw invalidResponse }
            return date.timeIntervalSince1970 > 0 ? date : nil
        }
        if let seconds = try number(["value": value], "value") {
            guard (0...253402300799).contains(seconds) else { throw invalidResponse }
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        throw invalidResponse
    }
    private static var invalidResponse: UsageError { .invalidResponse("Devin 客户端用量数据格式无效") }
}
