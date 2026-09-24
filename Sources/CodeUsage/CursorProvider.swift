import Foundation

private struct CursorAuth: Sendable {
    let accessToken: String
    let refreshToken: String?
    let sessionAccountId: String?
}

actor CursorProvider {
    private let databasePath = "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    private var inMemoryAccessToken: String?

    func fetch(individualLimitCents: Int64? = nil) async throws -> ProviderSnapshot {
        let databasePath = self.databasePath
        let auth = try await Task.detached(priority: .utility) {
            try Self.readAuth(databasePath: databasePath)
        }.value
        var accessToken = inMemoryAccessToken ?? auth.accessToken
        var usage = try await requestUsage(accessToken: accessToken)

        if usage.statusCode == 401 || usage.statusCode == 403 {
            guard let refreshToken = auth.refreshToken else {
                throw UsageError.notSignedIn("Cursor 登录已过期，请打开 Cursor 重新登录")
            }
            accessToken = try await refresh(refreshToken: refreshToken)
            inMemoryAccessToken = accessToken
            usage = try await requestUsage(accessToken: accessToken)
        }
        guard (200..<300).contains(usage.statusCode) else {
            if usage.statusCode == 401 || usage.statusCode == 403 {
                throw UsageError.notSignedIn("Cursor 登录已过期，请打开 Cursor 重新登录")
            }
            throw UsageError.requestFailed("Cursor 用量请求失败（HTTP \(usage.statusCode)）")
        }

        let plan = try? await requestPlan(accessToken: accessToken)
        let personalSummary: HTTPResult?
        if let sessionAccountId = auth.sessionAccountId, !sessionAccountId.isEmpty,
           let response = try? await requestPersonalSummary(
                accessToken: accessToken,
                sessionAccountId: sessionAccountId
           ), (200..<300).contains(response.statusCode) {
            personalSummary = response
        } else {
            personalSummary = nil
        }
        return try Self.map(
            usageData: usage.data,
            planData: plan?.data,
            personalSummaryData: personalSummary?.data,
            individualLimitCents: individualLimitCents
        )
    }

    private static func readAuth(databasePath: String) throws -> CursorAuth {
        let path = ProcessUtils.expandedHome(databasePath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.notInstalled("未找到 Cursor，请先安装并登录 Cursor")
        }
        func value(_ key: String) -> String? {
            let sql = "SELECT value FROM ItemTable WHERE key='\(key)' LIMIT 1;"
            guard let result = try? ProcessUtils.run(
                executable: "/usr/bin/sqlite3",
                arguments: ["-readonly", path, sql]
            ), result.status == 0 else { return nil }
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let access = value("cursorAuth/accessToken") else {
            throw UsageError.notSignedIn("Cursor 尚未登录")
        }
        return CursorAuth(
            accessToken: access,
            refreshToken: value("cursorAuth/refreshToken"),
            sessionAccountId: value("cursorAuth/stripeMembershipAuthId")
        )
    }

    private struct HTTPResult: Sendable {
        let statusCode: Int
        let data: Data
    }

    private func requestUsage(accessToken: String) async throws -> HTTPResult {
        try await connectPOST(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!,
            accessToken: accessToken
        )
    }

    private func requestPlan(accessToken: String) async throws -> HTTPResult {
        try await connectPOST(
            url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!,
            accessToken: accessToken
        )
    }

    private func requestPersonalSummary(
        accessToken: String,
        sessionAccountId: String
    ) async throws -> HTTPResult {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(
            "WorkosCursorSessionToken=\(sessionAccountId)::\(accessToken)",
            forHTTPHeaderField: "Cookie"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.invalidResponse("Cursor 返回了无效响应")
        }
        return HTTPResult(statusCode: http.statusCode, data: data)
    }

    private func connectPOST(url: URL, accessToken: String) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UsageError.invalidResponse("Cursor 返回了无效响应")
            }
            return HTTPResult(statusCode: http.statusCode, data: data)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.requestFailed("无法连接 Cursor：\(error.localizedDescription)")
        }
    }

    private func refresh(refreshToken: String) async throws -> String {
        let url = URL(string: "https://api2.cursor.sh/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
            "refresh_token": refreshToken
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["shouldLogout"] as? Bool != true,
              let token = object["access_token"] as? String,
              !token.isEmpty else {
            throw UsageError.notSignedIn("Cursor 登录已过期，请打开 Cursor 重新登录")
        }
        return token
    }

    static func map(
        usageData: Data,
        planData: Data? = nil,
        personalSummaryData: Data? = nil,
        individualLimitCents: Int64? = nil,
        now: Date = Date()
    ) throws -> ProviderSnapshot {
        guard let body = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any],
              body["enabled"] as? Bool != false else {
            throw UsageError.invalidResponse("Cursor 未返回有效订阅用量")
        }

        let planName: String? = {
            guard let planData,
                  let planBody = try? JSONSerialization.jsonObject(with: planData) as? [String: Any],
                  let planInfo = planBody.dictionary("planInfo") else { return nil }
            return planInfo["planName"] as? String
        }()
        let spendUsage = body.dictionary("spendLimitUsage")
        let personalSummary: [String: Any]? = {
            guard let personalSummaryData,
                  let summary = try? JSONSerialization.jsonObject(with: personalSummaryData)
                    as? [String: Any] else { return nil }
            return summary
        }()
        let personalUsage = personalSummary?.dictionary("individualUsage")
        let personalPlan = personalUsage?.dictionary("plan")
        let personalOnDemand = personalUsage?.dictionary("onDemand")
        // This team billing mode omits individualUsed from the Connect response.
        // Its dashboard tracks the purchased allowance separately from bonus usage.
        let usesPersonalPlanAmount =
            (spendUsage?["limitType"] as? String)?.lowercased() == "team" &&
            spendUsage?["individualUsed"] == nil &&
            spendUsage?["individualRemaining"] == nil
        let subscriptionCategory = subscriptionCategory(
            planName: planName,
            spend: spendUsage
        )

        let reset = DateParsing.date(from: body["billingCycleEnd"])
        let cycleStart = DateParsing.date(from: body["billingCycleStart"])
            ?? DateParsing.date(from: body["billingCycleStartDate"])
        let cycleDuration: TimeInterval? = {
            guard let reset, let cycleStart else { return nil }
            let duration = reset.timeIntervalSince(cycleStart)
            return duration > 0 ? duration : nil
        }()
        var metrics: [UsageMetric] = []
        if let usage = body.dictionary("planUsage") {
            let total: Double? = {
                if usesPersonalPlanAmount {
                    if let limit = personalPlan?.double("limit"), limit > 0,
                       let used = personalPlan?.double("used") {
                        return used / limit * 100
                    }
                    if let limit = usage.double("limit"), limit > 0,
                       let included = usage.double("includedSpend") {
                        return included / limit * 100
                    }
                }
                // Keep Cursor's reported percentage for the original billing mode.
                if let reported = usage.double("totalPercentUsed") {
                    return reported
                }
                if let limit = usage.double("limit"), limit > 0 {
                    if let included = usage.double("includedSpend") {
                        return included / limit * 100
                    }
                    if let totalSpend = usage.double("totalSpend") {
                        return totalSpend / limit * 100
                    }
                    if let remaining = usage.double("remaining") {
                        return (limit - remaining) / limit * 100
                    }
                }
                return nil
            }()
            if let total {
                let personalPlanValue: UsageMetricValue? = {
                    guard usesPersonalPlanAmount else { return nil }
                    if let limit = cents(positive(personalPlan?.double("limit"))),
                       let used = cents(personalPlan?.double("used")) {
                        return .usd(usedCents: used, limitCents: limit)
                    }
                    if let limit = cents(positive(usage.double("limit"))),
                       let used = cents(usage.double("includedSpend")) {
                        return .usd(usedCents: used, limitCents: limit)
                    }
                    return nil
                }()
                metrics.append(UsageMetric(
                    id: "total",
                    title: usesPersonalPlanAmount ? "基础套餐额度" : "总用量",
                    usedPercent: total,
                    deadlineAt: reset,
                    windowDuration: cycleDuration,
                    group: .included,
                    value: personalPlanValue
                ))
            }
            // In this team billing mode Auto is a routing choice: requests can
            // consume either model pool. autoPercentUsed is not Auto request use.
            if !usesPersonalPlanAmount,
               let auto = usage.double("autoPercentUsed") {
                metrics.append(UsageMetric(
                    id: "auto",
                    title: "Auto",
                    usedPercent: auto,
                    deadlineAt: reset,
                    windowDuration: cycleDuration,
                    group: .included
                ))
            }
            if let api = usage.double("apiPercentUsed") {
                metrics.append(UsageMetric(
                    id: "api",
                    title: usesPersonalPlanAmount
                        ? "第三方模型（API）"
                        : "其他模型（API）",
                    usedPercent: api,
                    deadlineAt: reset,
                    windowDuration: cycleDuration,
                    group: .included
                ))
            }
        }

        if spendUsage != nil || personalOnDemand != nil {
            let spend = spendUsage ?? [:]
            let providerIndividualLimit = cents(positive(
                spend.double("individualLimit") ?? personalOnDemand?.double("limit")
            ))
            let configuredIndividualLimit = individualLimitCents.flatMap { $0 > 0 ? $0 : nil }
            let individualLimit = providerIndividualLimit ?? configuredIndividualLimit
            let connectIndividualUsed = usedAmount(
                in: spend,
                usedKey: "individualUsed",
                limit: providerIndividualLimit.map(Double.init),
                remainingKey: "individualRemaining"
            )
            // Only fall back to the personal summary when Connect omits this member.
            // totalSpend also includes free bonus usage, and pooledUsed is team-wide.
            let summaryIndividualUsed = usesPersonalPlanAmount
                ? personalOnDemand?.double("used") : nil
            if let individualUsed = cents(connectIndividualUsed ?? summaryIndividualUsed) {
                let hasLimit = individualLimit != nil
                let percent = individualLimit.map {
                    Double(individualUsed) / Double($0) * 100
                } ?? 0
                metrics.append(UsageMetric(
                    id: "on_demand_personal",
                    title: subscriptionCategory.hasSharedOrganizationContext
                        ? "我的消费"
                        : "本期消费",
                    usedPercent: percent,
                    deadlineAt: hasLimit ? reset : nil,
                    windowDuration: hasLimit ? cycleDuration : nil,
                    group: .onDemand,
                    value: .usd(
                        usedCents: individualUsed,
                        limitCents: individualLimit
                    ),
                    showsProgress: hasLimit,
                    allowsLimitEditing: providerIndividualLimit == nil
                ))
            }

            if let pooledLimit = positive(spend.double("pooledLimit")),
               let pooledUsed = usedAmount(
                   in: spend,
                   usedKey: "pooledUsed",
                   limit: pooledLimit,
                   remainingKey: "pooledRemaining"
               ),
               let pooledLimitCents = cents(pooledLimit),
               let pooledUsedCents = cents(pooledUsed) {
                metrics.append(UsageMetric(
                    id: "on_demand_team",
                    title: subscriptionCategory == .enterprise
                        ? "组织总消费"
                        : "团队总消费",
                    usedPercent: pooledUsed / pooledLimit * 100,
                    deadlineAt: reset,
                    windowDuration: cycleDuration,
                    group: .onDemand,
                    value: .usd(
                        usedCents: pooledUsedCents,
                        limitCents: pooledLimitCents
                    )
                ))
            }
        }
        guard !metrics.isEmpty else {
            throw UsageError.invalidResponse("Cursor 用量响应格式已变化")
        }

        let missingPersonalSpending = subscriptionCategory.hasSharedOrganizationContext &&
            metrics.contains { $0.id == "on_demand_team" } &&
            !metrics.contains { $0.id == "on_demand_personal" }

        return ProviderSnapshot(
            provider: .cursor,
            planName: planName,
            metrics: metrics,
            fetchedAt: now,
            note: missingPersonalSpending ? "个人按量消费暂不可用；此处只显示团队或组织总消费。" : nil,
            subscriptionCategory: subscriptionCategory
        )
    }

    private static func subscriptionCategory(
        planName: String?,
        spend: [String: Any]?
    ) -> SubscriptionCategory {
        let normalizedPlan = planName?
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ") ?? ""
        let limitType = (spend?["limitType"] as? String)?.lowercased() ?? ""

        if normalizedPlan.contains("enterprise") || limitType.contains("enterprise") {
            return .enterprise
        }
        if limitType == "team" ||
            spend?["pooledLimit"] != nil ||
            spend?["pooledUsed"] != nil ||
            spend?["pooledRemaining"] != nil ||
            normalizedPlan.contains("team") ||
            normalizedPlan.contains("business") {
            return .team
        }
        if normalizedPlan.contains("trial") ||
            normalizedPlan.contains("free") ||
            normalizedPlan.contains("hobby") {
            return .freeTrial
        }
        if limitType == "individual" ||
            limitType == "personal" ||
            !normalizedPlan.isEmpty {
            return .individual
        }
        return .unknown
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func cents(_ value: Double?) -> Int64? {
        guard let value, value.isFinite, value >= 0,
              value <= Double(Int64.max) else { return nil }
        return Int64(value.rounded())
    }

    private static func usedAmount(
        in dictionary: [String: Any],
        usedKey: String,
        limit: Double?,
        remainingKey: String
    ) -> Double? {
        if let used = dictionary.double(usedKey), used >= 0 { return used }
        guard let limit,
              let remaining = dictionary.double(remainingKey),
              remaining >= 0 else { return nil }
        return max(limit - remaining, 0)
    }

}
