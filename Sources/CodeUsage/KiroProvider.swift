import Foundation

private struct KiroAuth: Sendable {
    let accessToken: String
    let profileArn: String?
    let authMethod: String?
    let provider: String?
    let region: String
    let expiresAt: Date?
    let origin: String
}

actor KiroProvider {
    private static let ideTokenPath = "~/.aws/sso/cache/kiro-auth-token.json"
    private static let cliDatabasePath = "~/Library/Application Support/kiro-cli/data.sqlite3"

    func fetch() async throws -> ProviderSnapshot {
        let authCandidates = try await Task.detached(priority: .utility) {
            try Self.readAuthCandidates()
        }.value

        var lastRejectedAuth: KiroAuth?
        for auth in authCandidates {
            var response = try await requestUsage(auth: auth, legacyPath: false)
            if response.statusCode == 404 {
                response = try await requestUsage(auth: auth, legacyPath: true)
            }
            if (200..<300).contains(response.statusCode) {
                let provider = auth.provider?.lowercased()
                let authMethod = auth.authMethod?.lowercased()
                let supportsPurchasedAddOns = authMethod == "social" || provider == "builderid"
                return try Self.map(
                    usageData: response.data,
                    includePurchasedAddOns: supportsPurchasedAddOns
                )
            }
            let serviceReason = Self.serviceReason(from: response.data)
            if response.statusCode == 403,
               serviceReason?.uppercased() == "FEATURE_NOT_SUPPORTED" {
                throw UsageError.invalidResponse("Kiro 当前登录方式或计划不支持读取个人 credits")
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                lastRejectedAuth = auth
                continue
            }
            throw UsageError.requestFailed("Kiro 用量请求失败（HTTP \(response.statusCode)）")
        }

        let expired = lastRejectedAuth?.expiresAt.map { $0 <= Date() } ?? false
        throw UsageError.notSignedIn(expired
            ? "Kiro 登录已过期，请打开 Kiro 重新登录"
            : "Kiro 登录状态不可用，请打开 Kiro 后重试")
    }

    private struct HTTPResult: Sendable {
        let statusCode: Int
        let data: Data
    }

    private func requestUsage(auth: KiroAuth, legacyPath: Bool) async throws -> HTTPResult {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "management.\(auth.region).kiro.dev"
        components.path = legacyPath ? "/getUsageLimits" : "/Get-Usage-Limits"
        var queryItems = [URLQueryItem(name: "origin", value: auth.origin)]
        if let profileArn = auth.profileArn, !profileArn.isEmpty {
            queryItems.append(URLQueryItem(name: "profileArn", value: profileArn))
        }
        if legacyPath {
            queryItems.append(URLQueryItem(name: "resourceType", value: "AGENTIC_REQUEST"))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw UsageError.requestFailed("无法生成 Kiro 用量请求地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch auth.authMethod?.lowercased() {
        case "idc":
            request.setValue("SSO_OIDC", forHTTPHeaderField: "TokenType")
        case "external_idp":
            request.setValue("EXTERNAL_IDP", forHTTPHeaderField: "TokenType")
        case "machine_token":
            request.setValue("KIRO_MACHINE_TOKEN", forHTTPHeaderField: "TokenType")
        case "api_key":
            request.setValue("API_KEY", forHTTPHeaderField: "TokenType")
        default:
            break
        }
        if auth.provider?.lowercased() == "internal" {
            request.setValue("true", forHTTPHeaderField: "redirect-for-internal")
        }

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UsageError.invalidResponse("Kiro 返回了无效响应")
            }
            return HTTPResult(statusCode: http.statusCode, data: data)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.requestFailed("无法连接 Kiro：\(error.localizedDescription)")
        }
    }

    private static func readAuthCandidates() throws -> [KiroAuth] {
        let environment = ProcessInfo.processInfo.environment
        let tokenPath = environment["KIRO_AUTH_TOKEN_PATH"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? ideTokenPath
        let expandedTokenPath = ProcessUtils.expandedHome(tokenPath)
        let profileArn = readStoredProfileArn()
        var candidates: [KiroAuth] = []

        if let object = try? readSecureJSONObject(at: expandedTokenPath),
           let auth = auth(from: object, fallbackProfileArn: profileArn) {
            candidates.append(auth)
        }

        let databasePath = environment["KIRO_CLI_DATABASE_PATH"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? cliDatabasePath
        let cliAuthCandidates = readCLIAuthCandidates(
            databasePath: ProcessUtils.expandedHome(databasePath),
            fallbackProfileArn: profileArn
        )
        for auth in cliAuthCandidates {
            if !candidates.contains(where: { $0.accessToken == auth.accessToken }) {
                candidates.append(auth)
            }
        }

        guard !candidates.isEmpty else {
            throw UsageError.notSignedIn("Kiro 尚未登录，请打开 Kiro 完成登录")
        }
        let now = Date()
        let current = candidates.filter { $0.expiresAt.map { $0 > now } ?? true }
        let expired = candidates.filter { $0.expiresAt.map { $0 <= now } ?? false }
        return current + expired
    }

    private static func readSecureJSONObject(at path: String) throws -> Any {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.notSignedIn("Kiro 尚未登录")
        }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw UsageError.invalidResponse("Kiro 登录文件不是安全的常规文件")
        }
        guard (values.fileSize ?? 0) <= 2_000_000 else {
            throw UsageError.invalidResponse("Kiro 登录文件异常过大")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func readCLIAuthCandidates(
        databasePath: String,
        fallbackProfileArn: String?
    ) -> [KiroAuth] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        let tokenKeys = [
            "kirocli:social:token",
            "kirocli:odic:token",
            "kirocli:external-idp:token",
            "codewhisperer:odic:token"
        ]
        let quotedKeys = tokenKeys.map { "'\($0)'" }.joined(separator: ",")
        let sql = "SELECT key || char(31) || hex(value) FROM auth_kv WHERE key IN (\(quotedKeys));"
        guard let result = try? ProcessUtils.run(
            executable: "/usr/bin/sqlite3",
            arguments: ["-readonly", databasePath, sql],
            timeout: 5
        ), result.status == 0 else { return [] }

        let rows = result.stdout.split(whereSeparator: \Character.isNewline)
        var parsedByKey: [String: KiroAuth] = [:]
        for row in rows {
            let columns = row.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            guard columns.count == 2,
                  let data = data(fromHex: String(columns[1])),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { continue }
            let key = String(columns[0])
            let fallbackMethod: String?
            let fallbackProvider: String?
            if key.contains("social") {
                fallbackMethod = "social"
                fallbackProvider = nil
            } else if key.contains("external-idp") {
                fallbackMethod = "external_idp"
                fallbackProvider = "ExternalIdp"
            } else {
                fallbackMethod = "IdC"
                fallbackProvider = "BuilderId"
            }
            if let auth = auth(
                from: object,
                fallbackProfileArn: fallbackProfileArn,
                fallbackAuthMethod: fallbackMethod,
                fallbackProvider: fallbackProvider,
                origin: "KIRO_CLI"
            ) {
                parsedByKey[key] = auth
            }
        }
        return tokenKeys.compactMap { parsedByKey[$0] }
    }

    private static func readStoredProfileArn() -> String? {
        let candidates = [
            "~/Library/Application Support/Kiro/User/globalStorage/kiro.kiro-agent/profile.json",
            "~/Library/Application Support/Kiro/User/globalStorage/kiroAgent/profile.json"
        ]
        for candidate in candidates {
            let path = ProcessUtils.expandedHome(candidate)
            guard let object = try? readSecureJSONObject(at: path),
                  let arn = findString(named: ["arn", "profilearn"], in: object)
            else { continue }
            return arn
        }
        return nil
    }

    private static func auth(
        from object: Any,
        fallbackProfileArn: String?,
        fallbackAuthMethod: String? = nil,
        fallbackProvider: String? = nil,
        origin: String = "AI_EDITOR"
    ) -> KiroAuth? {
        let accessToken: String?
        if let raw = object as? String, !raw.isEmpty, !raw.hasPrefix("{") {
            accessToken = raw
        } else {
            accessToken = findString(named: ["accesstoken"], in: object)
        }
        guard let accessToken, !accessToken.isEmpty else { return nil }

        let profileArn = findString(named: ["profilearn"], in: object) ?? fallbackProfileArn
        let provider = findString(named: ["provider"], in: object) ?? fallbackProvider
        let storedAuthMethod = findString(named: ["authmethod"], in: object) ?? fallbackAuthMethod
        let authMethod = sanitizedAuthMethod(provider: provider, storedAuthMethod: storedAuthMethod)
        let region = sanitizedRegion(
            arnRegion(profileArn)
                ?? findString(named: ["region", "ssoregion", "idcregion"], in: object)
                ?? "us-east-1"
        )
        let expiresAt = findValue(named: ["expiresat", "expiration", "expiry"], in: object)
            .flatMap { DateParsing.date(from: $0) }

        return KiroAuth(
            accessToken: accessToken,
            profileArn: profileArn,
            authMethod: authMethod,
            provider: provider,
            region: region,
            expiresAt: expiresAt,
            origin: origin
        )
    }

    private static func findString(named names: Set<String>, in object: Any) -> String? {
        guard let value = findValue(named: names, in: object) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func findValue(
        named names: Set<String>,
        in object: Any,
        depth: Int = 0
    ) -> Any? {
        guard depth < 7 else { return nil }
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where names.contains(normalizedKey(key)) {
                return value
            }
            for value in dictionary.values {
                if let match = findValue(named: names, in: value, depth: depth + 1) {
                    return match
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let match = findValue(named: names, in: value, depth: depth + 1) {
                    return match
                }
            }
        } else if let string = object as? String,
                  let data = string.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  !(nested is String) {
            return findValue(named: names, in: nested, depth: depth + 1)
        }
        return nil
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func sanitizedAuthMethod(
        provider: String?,
        storedAuthMethod: String?
    ) -> String? {
        switch provider?.lowercased() {
        case "google", "github":
            return "social"
        case "enterprise", "builderid", "internal":
            return "IdC"
        case "externalidp":
            return "external_idp"
        default:
            return storedAuthMethod
        }
    }

    private static func arnRegion(_ arn: String?) -> String? {
        guard let arn else { return nil }
        let components = arn.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count > 3, !components[3].isEmpty else { return nil }
        return String(components[3])
    }

    private static func sanitizedRegion(_ region: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return region.unicodeScalars.allSatisfy(allowed.contains) && !region.isEmpty
            ? region
            : "us-east-1"
    }

    private static func data(fromHex string: String) -> Data? {
        guard string.count.isMultiple(of: 2), string.allSatisfy(\.isHexDigit) else { return nil }
        var data = Data()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func serviceReason(from data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return findString(named: ["reason"], in: body)
    }

    static func map(
        usageData: Data,
        includePurchasedAddOns: Bool = true,
        now: Date = Date()
    ) throws -> ProviderSnapshot {
        guard let body = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any] else {
            throw UsageError.invalidResponse("Kiro 用量响应格式不正确")
        }

        let rootReset = validResetDate(from: body["nextDateReset"])
        let breakdowns = (body["usageBreakdownList"] as? [[String: Any]])
            ?? body.dictionary("usageBreakdown").map { [$0] }
            ?? []
        let selectedBreakdown = breakdowns
            .filter { usageLimit(in: $0) > 0 && usageLimit(in: $0) < 999_999 }
            .max { breakdownScore($0) < breakdownScore($1) }

        let used: Double
        let limit: Double
        let usedPercent: Double
        let reset: Date?
        let bonusDescription: String?
        var addOnMetric: UsageMetric?

        if let selectedBreakdown {
            used = max(currentUsage(in: selectedBreakdown), 0)
            limit = usageLimit(in: selectedBreakdown)
            usedPercent = limit > 0 ? used / limit * 100 : 0
            reset = validResetDate(from: selectedBreakdown["nextDateReset"]) ?? rootReset
            bonusDescription = bonusNote(from: selectedBreakdown, now: now)
            addOnMetric = includePurchasedAddOns
                ? purchasedAddOnMetric(from: selectedBreakdown, now: now)
                : nil
        } else if let selectedLimit = preferredLegacyLimit(in: body) {
            used = max(selectedLimit.double("currentUsage") ?? 0, 0)
            limit = selectedLimit.double("totalUsageLimit") ?? 0
            if let percent = selectedLimit.double("percentUsed") {
                usedPercent = percent
            } else {
                usedPercent = limit > 0 ? used / limit * 100 : 0
            }
            reset = rootReset
            bonusDescription = nil
            addOnMetric = nil
        } else {
            throw UsageError.invalidResponse("Kiro 未返回可计量的 credits 额度")
        }

        guard used.isFinite, limit.isFinite, usedPercent.isFinite, limit > 0 else {
            throw UsageError.invalidResponse("Kiro 当前计划未提供 credits 上限")
        }

        let rawPlan = body.dictionary("subscriptionInfo")?["subscriptionTitle"] as? String
        let planName = normalizedPlanName(rawPlan)
        var metrics = [UsageMetric(
            id: "credits",
            title: "月度 Credits",
            usedPercent: usedPercent,
            deadlineAt: reset,
            windowDuration: reset.flatMap(monthlyWindowDuration),
            group: .included,
            value: .quantity(
                used: used,
                limit: limit,
                remaining: nil,
                unit: "credits"
            )
        )]
        if let addOnMetric {
            metrics.append(addOnMetric)
        }

        return ProviderSnapshot(
            provider: .kiro,
            planName: planName,
            metrics: metrics,
            fetchedAt: now,
            note: bonusDescription,
            subscriptionCategory: .inferred(from: planName)
        )
    }

    private static func currentUsage(in breakdown: [String: Any]) -> Double {
        breakdown.double("currentUsageWithPrecision")
            ?? breakdown.double("currentUsage")
            ?? 0
    }

    private static func usageLimit(in breakdown: [String: Any]) -> Double {
        breakdown.double("usageLimitWithPrecision")
            ?? breakdown.double("usageLimit")
            ?? 0
    }

    private static func breakdownScore(_ breakdown: [String: Any]) -> Int {
        let searchable = [
            breakdown["resourceType"] as? String,
            breakdown["displayName"] as? String,
            breakdown["displayNamePlural"] as? String,
            breakdown["unit"] as? String
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        var score = 0
        if searchable.contains("credit") { score += 100 }
        if searchable.contains("agentic_request") || searchable.contains("agentic request") {
            score += 50
        }
        if breakdown["currentUsageWithPrecision"] != nil { score += 10 }
        return score
    }

    private static func preferredLegacyLimit(in body: [String: Any]) -> [String: Any]? {
        guard let limits = body["limits"] as? [[String: Any]] else { return nil }
        return limits
            .filter { ($0.double("totalUsageLimit") ?? 0) > 0 }
            .max {
                legacyLimitScore($0) < legacyLimitScore($1)
            }
    }

    private static func legacyLimitScore(_ limit: [String: Any]) -> Int {
        let type = (limit["type"] as? String)?.lowercased() ?? ""
        if type.contains("credit") { return 100 }
        if type == "agentic_request" { return 50 }
        return 0
    }

    private static func bonusNote(from breakdown: [String: Any], now: Date) -> String? {
        var bonusRemaining = 0.0
        if let freeTrial = breakdown.dictionary("freeTrialInfo"),
           freeTrial["freeTrialStatus"] as? String == "ACTIVE",
           isNotExpired(freeTrial["freeTrialExpiry"], at: now) {
            bonusRemaining += remainingCredits(in: freeTrial)
        }
        if let bonuses = breakdown["bonuses"] as? [[String: Any]] {
            for bonus in bonuses {
                let status = bonus["status"] as? String
                guard (status == "ACTIVE" || status == "EXHAUSTED"),
                      isNotExpired(bonus["expiresAt"], at: now) else { continue }
                bonusRemaining += remainingCredits(in: bonus)
            }
        }

        if bonusRemaining > 0 {
            return "Bonus 剩余 \(formatCredits(bonusRemaining)) credits"
        }
        return nil
    }

    private static func purchasedAddOnMetric(
        from breakdown: [String: Any],
        now: Date
    ) -> UsageMetric? {
        guard let credits = breakdown["overageCredits"] as? [[String: Any]] else {
            return nil
        }
        var used = 0.0
        var limit = 0.0
        for credit in credits where isNotExpired(credit["expiresAt"], at: now) {
            used += credit.double("currentUsageWithPrecision")
                ?? credit.double("currentUsage")
                ?? 0
            limit += credit.double("usageLimitWithPrecision")
                ?? credit.double("usageLimit")
                ?? 0
        }
        guard used.isFinite, limit.isFinite, limit > 0 else { return nil }
        return UsageMetric(
            id: "add_on",
            title: "个人 Add-on",
            usedPercent: used / limit * 100,
            deadlineAt: nil,
            group: .personalAddOn,
            value: .quantity(
                used: used,
                limit: limit,
                remaining: nil,
                unit: "credits"
            )
        )
    }

    private static func isNotExpired(_ value: Any?, at now: Date) -> Bool {
        guard let value, let expiry = DateParsing.date(from: value) else { return true }
        return expiry > now
    }

    private static func remainingCredits(in pool: [String: Any]) -> Double {
        let used = pool.double("currentUsageWithPrecision")
            ?? pool.double("currentUsage")
            ?? 0
        let total = pool.double("usageLimitWithPrecision")
            ?? pool.double("usageLimit")
            ?? 0
        return max(total - used, 0)
    }

    private static func monthlyWindowDuration(endingAt reset: Date) -> TimeInterval? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return nil }
        let duration = reset.timeIntervalSince(start)
        return duration > 0 ? duration : nil
    }

    private static func validResetDate(from value: Any?) -> Date? {
        guard let date = DateParsing.date(from: value), date.timeIntervalSince1970 > 0 else {
            return nil
        }
        return date
    }

    private static func normalizedPlanName(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("kiro ") {
            value.removeFirst(5)
        }
        return value.lowercased().split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private static func formatCredits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
