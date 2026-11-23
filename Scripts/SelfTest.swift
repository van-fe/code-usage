import Darwin
import Foundation

@main
struct SelfTest {
    static func main() async throws {
        try codexSelectsWeeklyWindow()
        try codexMapsWorkspaceLimits()
        usageErrorsIdentifySignInFailures()
        codexIdentifiesSignInFailures()
        providerArchiveRoundTripsKnownProviders()
        try cloudSnapshotContainsOnlyDisplayData()
        try sharedUsageSnapshotRoundTripsDisplayData()
        sharedUsageSnapshotResolvesLocalWidgetContainer()
        sharedUsageSnapshotMirrorsLocalWidgetAlongsideAppGroup()
        sharedUsageSnapshotReadsHostSupportFromSandbox()
        sharedUsageSnapshotUsesOnlyAppGroupInProduction()
        try cursorMapsReportedMetrics()
        try cursorDecodesEncryptedCredentials()
        try await cursorCachesCredentials()
        try cursorPreservesOriginalBillingFields()
        try cursorCalculatesTotalWhenMissing()
        try cursorUsesPersonalSummaryWhenTeamOmitsIndividualSpend()
        try cursorMapsOnDemandUsage()
        try cursorPrefersProviderIndividualLimit()
        try cursorKeepsSpendWithoutIndividualLimit()
        try cursorMapsSpendWithoutPlanUsage()
        try cursorLabelsPersonalAndTeamUsage()
        try claudeMapsWeeklyAndSessionWindows()
        kiroParsesCLIAuthRows()
        try kiroMergesRefreshedIDECredential()
        try kiroMergesRefreshedCLICredential()
        try kiroRejectsMalformedRefreshResponse()
        try kiroMapsPreciseCreditsAndExtras()
        try kiroFallsBackToLegacyLimits()
        try kiroRejectsMissingQuota()
        try qoderMapsPlanAddOnAndSharedCredits()
        try qoderPreservesCLISmallPercentages()
        try qoderRejectsNotificationFlood()
        try qoderRejectsUnsafeDiscoveryPermissions()
        try qoderBinarySelectionRejectsExecutableDirectories()
        qoderInstallationRecognizesOverrides()
        try devinCoversPlanBillingModels()
        try clientProvidersMapUsage()
        try clientProvidersValidateCredentialsAndRequests()
        subscriptionSimulationBuildsFourCategories()
        suggestedUsageTracksElapsedWindow()
        print("CodeUsage mapper tests passed")
    }

    private static func devinCoversPlanBillingModels() throws {
        func snapshot(_ name: String, _ fields: [String: Any], info: [String: Any] = [:]) throws -> ProviderSnapshot {
            var info = info
            info["planName"] = name
            var plan = fields
            plan["planInfo"] = info
            let data = try JSONSerialization.data(withJSONObject: ["userStatus": ["planStatus": plan]])
            return try DevinProvider.map(data: data)
        }
        func quantity(_ metric: UsageMetric, used: Double?, limit: Double?, remaining: Double?, unit: String) {
            precondition(metric.value == .quantity(used: used, limit: limit, remaining: remaining, unit: unit))
        }
        let reset = 2_030_000_000.0
        let pro = try snapshot("Pro", ["dailyQuotaRemainingPercent": 100, "weeklyQuotaRemainingPercent": 25,
            "dailyQuotaResetAtUnix": String(Int(reset)), "weeklyQuotaResetAtUnix": reset + 86400,
            "overageBalanceMicros": "12505000", "acuConsumed": 2.5, "acuLimit": 10,
            "dollarsConsumed": 4.25, "dollarsLimit": 20], info: ["billingStrategy": "BILLING_STRATEGY_QUOTA"])
        precondition(pro.metrics.map(\.id) == ["daily", "weekly", "acu", "dollars", "overage_balance"])
        precondition(pro.metrics.map(\.usedPercent) == [0, 75, 25, 21.25, 0])
        quantity(pro.metrics.last!, used: nil, limit: nil, remaining: 12.505, unit: "USD")
        precondition(!pro.metrics.last!.showsProgress && pro.metrics.last!.deadlineAt == nil)
        let max = try snapshot("Max", ["weeklyQuotaRemainingPercent": 70],
            info: ["billingStrategy": 2, "hideDailyQuota": true])
        precondition(max.metrics.map(\.id) == ["weekly", "overage_balance"])
        precondition(max.metrics.first?.usedPercent == 30 && max.metrics.first?.deadlineAt == nil)
        let teams = try snapshot("Teams", ["overageBalanceMicros": "80000000", "dollarsConsumed": 15, "dollarsLimit": 100],
            info: ["isTeams": true, "billingStrategy": "BILLING_STRATEGY_QUOTA", "hideDailyQuota": true, "hideWeeklyQuota": true])
        precondition(teams.subscriptionCategory == .team && teams.metrics.map(\.id) == ["dollars", "overage_balance"])
        precondition(teams.metrics.last?.title == "共享按量余额" && teams.metrics.last?.group == .organizationShared)
        quantity(teams.metrics.last!, used: nil, limit: nil, remaining: 80, unit: "USD")
        let enterprise = try snapshot("Enterprise", ["acuConsumed": 125.5, "acuLimit": 500,
            "dollarsConsumed": 31.25, "dollarsLimit": 200], info: ["isEnterprise": true, "billingStrategy": 3])
        precondition(enterprise.subscriptionCategory == .enterprise && enterprise.metrics.map(\.id) == ["acu", "dollars"])
        let limited = try snapshot("Enterprise", ["acuLimit": 500, "dollarsLimit": 200], info: ["billingStrategy": 3])
        precondition(limited.metrics.allSatisfy { !$0.showsProgress })
        quantity(limited.metrics[0], used: nil, limit: 500, remaining: nil, unit: "ACU")
        let unlimited = try snapshot("Enterprise", ["acuConsumed": 12, "acuLimit": -1, "dollarsConsumed": 5, "dollarsLimit": -1], info: ["billingStrategy": 3])
        precondition(unlimited.metrics.allSatisfy { !$0.showsProgress && $0.title.contains("不限量") })
        quantity(unlimited.metrics[0], used: 12, limit: nil, remaining: nil, unit: "ACU")
        let credits = try snapshot("Enterprise", ["availablePromptCredits": 100000, "usedPromptCredits": 25025,
            "availableFlowCredits": 50000, "usedFlowCredits": 12500,
            "availableFlexCredits": 20000, "usedFlexCredits": 5025,
            "planStart": "2030-01-01T00:00:00Z", "planEnd": "2030-02-01T00:00:00Z"],
            info: ["isEnterprise": true, "billingStrategy": "BILLING_STRATEGY_CREDITS"])
        precondition(credits.metrics.map(\.id) == ["prompt_credits", "flow_credits", "add_on_credits"])
        quantity(credits.metrics[0], used: 250.25, limit: 1000, remaining: 749.75, unit: "Credits")
        quantity(credits.metrics[2], used: 50.25, limit: 200, remaining: 149.75, unit: "Credits")
        precondition(credits.metrics[0].usedPercent == 25.025)
        precondition(credits.metrics[0].deadlineAt == DateParsing.date(from: "2030-02-01T00:00:00Z"))
        precondition(credits.metrics[2].deadlineAt == nil && credits.metrics[2].windowDuration == nil)
        precondition(credits.metrics[2].group == .organizationShared)
        let legacyUnlimited = try snapshot("Enterprise", ["availablePromptCredits": -1, "usedPromptCredits": 100,
            "availableFlexCredits": 0], info: ["billingStrategy": 1])
        quantity(legacyUnlimited.metrics[0], used: 1, limit: nil, remaining: nil, unit: "Credits")
        precondition(!legacyUnlimited.metrics[0].showsProgress)
        let overLimit = try snapshot("Enterprise", ["availablePromptCredits": 100, "usedPromptCredits": 125], info: ["billingStrategy": 1])
        quantity(overLimit.metrics[0], used: 1.25, limit: 1, remaining: 0, unit: "Credits")
        precondition(overLimit.metrics[0].usedPercent == 125 && overLimit.metrics[0].clampedPercent == 100)
        let zeroes = try snapshot("Legacy", ["availablePromptCredits": 10000], info: ["billingStrategy": 1])
        quantity(zeroes.metrics[0], used: 0, limit: 100, remaining: 100, unit: "Credits")
        let free = try snapshot("Free", [:])
        precondition(free.subscriptionCategory == .freeTrial && free.metrics.isEmpty && free.note != nil)
        let unknown = try snapshot("Custom", [:])
        precondition(unknown.planName == "Custom" && unknown.metrics.isEmpty)
        let staleCredits = try snapshot("Pro", ["availablePromptCredits": 100, "usedPromptCredits": 50,
            "dailyQuotaRemainingPercent": 80], info: ["billingStrategy": 2, "hideWeeklyQuota": true])
        precondition(!staleCredits.metrics.contains { $0.id.contains("credits") })
        for original in [pro, max, teams, enterprise, limited, unlimited, credits, legacyUnlimited, free] {
            _ = try CloudUsageSnapshot(snapshot: original).encoded()
        }
        for fields: [String: Any] in [["acuConsumed": true], ["acuLimit": -2], ["dollarsConsumed": "NaN"],
            ["dollarsLimit": "inf"], ["overageBalanceMicros": false], ["availablePromptCredits": -2],
            ["weeklyQuotaRemainingPercent": "bad"], ["dailyQuotaResetAtUnix": -1], ["planEnd": "not-a-date"]] {
            do { _ = try snapshot("Test", fields, info: ["billingStrategy": 1]); preconditionFailure("Invalid Devin field accepted: \(fields.keys.sorted())") }
            catch is UsageError { }
        }
    }

    private static func clientProvidersMapUsage() throws {
        let data = Data("""
        {"is_available":true,"balance_infos":[
          {"currency":"CNY","total_balance":"110.25","granted_balance":"10.25","topped_up_balance":"100.00"},
          {"currency":"USD","total_balance":"0.00","granted_balance":"0.00","topped_up_balance":"0.00"}
        ]}
        """.utf8)
        let snapshot = try DeepSeekProvider.mapAPI(data: data)
        precondition(snapshot.metrics.count == 6 && snapshot.metrics.allSatisfy { !$0.showsProgress })
        precondition(snapshot.primaryMetric?.id == "balance_CNY")
        precondition(snapshot.widgetPrimaryMetric?.id == "balance_CNY")
        precondition(UsageMetricDisplayFormatter.compactValueText(snapshot.metrics[0]) == "¥110.25")
        precondition(UsageMetricDisplayFormatter.compactValueText(snapshot.metrics[3]) == "$0")
        let unavailable = try DeepSeekProvider.mapAPI(data: Data("""
        {"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0","granted_balance":"0","topped_up_balance":"0"}]}
        """.utf8))
        precondition(unavailable.note != nil && unavailable.metrics.count == 3)
        let devin = try DevinProvider.map(data: Data("""
        {"userStatus":{"planStatus":{"planInfo":{"planName":"Pro"},"dailyQuotaRemainingPercent":100,"weeklyQuotaRemainingPercent":27,"dailyQuotaResetAtUnix":"2030000000","weeklyQuotaResetAtUnix":"2030500000"}}}
        """.utf8))
        precondition(devin.subscriptionCategory == .individual && devin.planName == "Pro")
        precondition(devin.metrics.map(\.usedPercent) == [0, 73])
        precondition(devin.metrics.map(\.id) == ["daily", "weekly"])
        precondition(devin.metrics[1].deadlineAt == Date(timeIntervalSince1970: 2030500000))
        let exhausted = try DevinProvider.map(data: Data("""
        {"userStatus":{"planStatus":{"planInfo":{"planName":"Teams","isTeams":true,"hideDailyQuota":true},"dailyQuotaRemainingPercent":50,"dailyQuotaResetAtUnix":"2030000000","weeklyQuotaResetAtUnix":"2030500000"}}}
        """.utf8))
        precondition(exhausted.metrics.count == 1 && exhausted.primaryMetric?.usedPercent == 100)
        precondition(exhausted.subscriptionCategory == .team)
        let acu = try DevinProvider.map(data: Data("""
        {"userStatus":{"planStatus":{"planInfo":{"planName":"Enterprise","isEnterprise":true},"acuConsumed":12.5,"acuLimit":50}}}
        """.utf8))
        precondition(acu.primaryMetric?.usedPercent == 25 && acu.subscriptionCategory == .enterprise)
        let account = try DeepSeekProvider.mapAccount(data: Data("""
        {"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[{"currency":"CNY","balance":"100.25"}],"bonus_wallets":[{"currency":"CNY","balance":"10"}]}}}
        """.utf8))
        precondition(account.metrics.count == 2 && account.metrics.allSatisfy { !$0.showsProgress })
        precondition(account.metrics.map(\.id) == ["topped_up_CNY", "granted_CNY"])
        let cloud = String(decoding: try CloudUsageSnapshot(snapshot: account).encoded(), as: UTF8.self)
        precondition(!cloud.contains("apiKey") && !cloud.contains("token") && !cloud.contains("credentials"))
        for invalid in ["{}", "{\"is_available\":true,\"balance_infos\":[]}", "{\"is_available\":true,\"balance_infos\":[{\"currency\":\"USD\",\"total_balance\":\"nan\",\"granted_balance\":\"0\",\"topped_up_balance\":\"0\"}]}"] {
            do { _ = try DeepSeekProvider.mapAPI(data: Data(invalid.utf8)); preconditionFailure("Invalid balance accepted") }
            catch is UsageError { }
        }
        do {
            _ = try DevinProvider.map(data: Data("{\"userStatus\":{\"planStatus\":{\"planInfo\":{},\"dailyQuotaRemainingPercent\":101,\"dailyQuotaResetAtUnix\":2030000000}}}".utf8))
            preconditionFailure("Invalid Devin quota accepted")
        } catch is UsageError { }
        do {
            _ = try DeepSeekProvider.mapAccount(data: Data("{\"code\":40003}".utf8))
            preconditionFailure("Expired Harness login accepted")
        } catch let error as UsageError { precondition(error.requiresSignIn) }
    }

    private static func clientProvidersValidateCredentialsAndRequests() throws {
        let yaml = """
        version: 1
        records:
          client-connection/browser-session:
            kind: grant
            payload:
              version: 1
              secret: unrelated-fixture
        refs:
          OPENAI_API_KEY: unrelated-fixture
          DEEPSEEK_API_KEY: 'fixture-key'
        """
        let parsedKey = try DeepSeekProvider.parse(document: yaml)
        precondition(parsedKey == .apiKey("fixture-key"))
        let grant = """
        version: 1
        records:
          deepseek-account-platform/default:
            kind: grant
            payload:
              version: 1
              token: "fixture-account-token"
              issuer: https://platform.deepseek.com
        refs:
          DEEPSEEK_API_KEY: fallback-fixture
        """
        let parsedGrant = try DeepSeekProvider.parse(document: grant)
        precondition(parsedGrant == .accountToken("fixture-account-token"))
        for invalid in [yaml.replacingOccurrences(of: "version: 1", with: "version: 9"),
                        yaml + "  DEEPSEEK_API_KEY: duplicate\n",
                        grant.replacingOccurrences(of: "https://platform.deepseek.com", with: "https://other.example"),
                        "version: 1\nrefs:\n  DEEPSEEK_API_KEY: |\n    block\n"] {
            do { _ = try DeepSeekProvider.parse(document: invalid); preconditionFailure("Unsafe credentials accepted") }
            catch is UsageError { }
        }
        let request = try DevinProvider.request(apiKey: "fixture-secret", version: "1.2.3")
        try ProviderHTTPClient.validateDestination(request, provider: .devin)
        precondition(request.value(forHTTPHeaderField: "X-Api-Key") == "fixture-secret")
        precondition(!request.url!.absoluteString.contains("fixture-secret"))
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body.dictionary("metadata")?["ideName"] as? String == "windsurf")
        var invalidRequest = request
        invalidRequest.url = URL(string: "https://other.example/exa.seat_management_pb.SeatManagementService/GetUserStatus")!
        do { try ProviderHTTPClient.validateDestination(invalidRequest, provider: .devin); preconditionFailure("External credential destination accepted") }
        catch is UsageError { }
        for status in [301, 401, 403, 429, 500] {
            do { try ProviderHTTPClient.validateStatus(status, provider: .devin); preconditionFailure("HTTP error accepted") }
            catch let error as UsageError { precondition(error.requiresSignIn == (status == 401)) }
        }
    }

    private static func cursorCachesCredentials() async throws {
        let encrypted = "cursor-safe-storage:v1:djEwJLNOsxGboBLJL/oIMN4YkptVYFS59+ZUz0KktjwmOXo="
        let initial = CursorStoredAuth(accessToken: encrypted, refreshToken: encrypted, sessionAccountId: "account-a")
        let fixture = CursorCredentialFixture(initial)
        let store = CursorCredentialStore(readStored: { try fixture.read() }, readPassword: { try fixture.password() })
        let first = try await store.load()
        precondition(first.accessToken == "fixture.header.signature")
        precondition(fixture.passwordReads == 1, "Both encrypted tokens share one Keychain read")
        for _ in 0..<3 {
            let cached = try await store.load()
            precondition(cached == first)
        }
        precondition(fixture.passwordReads == 1, "Ordinary refreshes must not access Keychain")
        fixture.denyStoredRead = true
        do {
            _ = try await store.load()
            preconditionFailure("Unavailable database must fail without using cached credentials")
        } catch let error as UsageError { precondition(!error.requiresSignIn) }
        fixture.denyStoredRead = false
        let afterDatabaseRecovery = try await store.load()
        precondition(afterDatabaseRecovery == first && fixture.passwordReads == 1)
        await store.useRefreshedAccessToken("renewed-access", for: first)
        let renewed = try await store.load()
        precondition(renewed.accessToken == "renewed-access")
        precondition(fixture.passwordReads == 1)
        let reloaded = try await store.load(forceReload: true)
        precondition(reloaded == first)
        precondition(fixture.passwordReads == 2, "Authentication failure must reload Keychain")
        fixture.set(CursorStoredAuth(accessToken: encrypted, refreshToken: "rotated-refresh", sessionAccountId: "account-a"))
        let rotated = try await store.load()
        precondition(rotated.refreshToken == "rotated-refresh" && fixture.passwordReads == 3)
        fixture.set(CursorStoredAuth(accessToken: encrypted, refreshToken: "rotated-refresh", sessionAccountId: "account-b"))
        let switched = try await store.load()
        precondition(switched.sessionAccountId == "account-b" && fixture.passwordReads == 4)
        await store.useRefreshedAccessToken("old-account-token", for: first)
        let stillSwitched = try await store.load()
        precondition(stillSwitched == switched, "Stale refresh must not overwrite another account")
        fixture.set(CursorStoredAuth(accessToken: nil, refreshToken: nil, sessionAccountId: nil))
        do {
            _ = try await store.load()
            preconditionFailure("Signed-out account reused cached credentials")
        } catch let error as UsageError { precondition(error.requiresSignIn) }
        precondition(fixture.passwordReads == 4, "Logout must not access Keychain")
        fixture.set(initial)
        fixture.denyPassword = true
        do {
            _ = try await store.load()
            preconditionFailure("Keychain denial reused old credentials")
        } catch let error as UsageError { precondition(!error.requiresSignIn) }
        fixture.denyPassword = false
        let afterDenial = try await store.load()
        precondition(afterDenial == first && fixture.passwordReads == 6)
        let afterRetry = try await store.load()
        precondition(afterRetry == first && fixture.passwordReads == 6)
        fixture.set(CursorStoredAuth(accessToken: "new-access", refreshToken: "new-refresh", sessionAccountId: "account-c"))
        let plaintext = try await store.load()
        precondition(plaintext.accessToken == "new-access" && fixture.passwordReads == 6)
    }

    private static func cursorDecodesEncryptedCredentials() throws {
        let plain = try CursorCredentialCodec.decode("legacy.token.value") {
            preconditionFailure("Plaintext credentials must not access Keychain")
        }
        precondition(plain == "legacy.token.value")
        // Independently generated with OpenSSL AES-128-CBC and PBKDF2-SHA1.
        let encrypted = "cursor-safe-storage:v1:djEwJLNOsxGboBLJL/oIMN4YkptVYFS59+ZUz0KktjwmOXo="
        let decoded = try CursorCredentialCodec.decode(encrypted) { Data("fixture-password".utf8) }
        precondition(decoded == "fixture.header.signature")
        for malformed in ["cursor-safe-storage:v2:unknown", "cursor-safe-storage:v1:???",
                          "cursor-safe-storage:v1:djEwAA=="] {
            do {
                _ = try CursorCredentialCodec.decode(malformed) {
                    preconditionFailure("Invalid envelopes must not access Keychain")
                }
                preconditionFailure("Malformed ciphertext was accepted")
            } catch let error as UsageError {
                if case .invalidResponse = error {} else { preconditionFailure("Incorrect format error") }
            }
        }
        do {
            _ = try CursorCredentialCodec.decode(encrypted) { Data("wrong-password".utf8) }
            preconditionFailure("Wrong key was accepted")
        } catch let error as UsageError {
            precondition(!error.requiresSignIn)
        }
    }

    private static func codexSelectsWeeklyWindow() throws {
        let envelope: [String: Any] = [
            "result": [
                "rateLimits": [
                    "planType": "pro",
                    "primary": [
                        "usedPercent": 18,
                        "windowDurationMins": 300,
                        "resetsAt": 1_800_000_000
                    ],
                    "secondary": [
                        "usedPercent": 42,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_800_100_000
                    ]
                ]
            ]
        ]
        let snapshot = try CodexProvider.map(envelope)
        precondition(snapshot.primaryMetric?.usedPercent == 42)
        precondition(snapshot.primaryMetric?.windowDuration == 7 * 24 * 60 * 60)
        precondition(snapshot.metrics.map(\.id) == ["weekly", "session"])
        precondition(snapshot.metrics.allSatisfy { $0.group == .included })
        precondition(snapshot.planName == "Pro")
    }

    private static func codexMapsWorkspaceLimits() throws {
        let envelope: [String: Any] = [
            "result": [
                "rateLimits": [
                    "planType": "business",
                    "primary": [
                        "usedPercent": 20,
                        "windowDurationMins": 43_200,
                        "resetsAt": 1_900_000_000
                    ],
                    "individualLimit": [
                        "limit": 25_000,
                        "used": 8_000,
                        "remainingPercent": 68,
                        "resetsAt": 1_900_000_000
                    ],
                    "credits": [
                        "hasCredits": true,
                        "unlimited": false,
                        "balance": "1200.5"
                    ]
                ]
            ]
        ]
        let snapshot = try CodexProvider.map(envelope)
        precondition(snapshot.planName == "Business")
        precondition(snapshot.metrics.map(\.id) == [
            "window_43200", "individual_limit", "workspace_credits"
        ])
        precondition(snapshot.metrics[0].title == "30 天额度")
        precondition(snapshot.metrics[1].usedPercent == 32)
        precondition(snapshot.metrics[1].group == .credits)
        precondition(snapshot.metrics[2].showsProgress == false)
        guard case .quantity(_, _, let balance, _) = snapshot.metrics[2].value else {
            preconditionFailure("Expected workspace credits quantity")
        }
        precondition(balance == 1200.5)
    }

    private static func usageErrorsIdentifySignInFailures() {
        precondition(UsageError.notSignedIn("login").requiresSignIn)
        precondition(!UsageError.requestFailed("network").requiresSignIn)
    }

    private static func codexIdentifiesSignInFailures() {
        let authFailure = CodexProvider.requestFailure(message: "Login required")
        precondition(authFailure.requiresSignIn)
        let networkFailure = CodexProvider.requestFailure(message: "Connection reset")
        precondition(!networkFailure.requiresSignIn)
    }

    private static func providerArchiveRoundTripsKnownProviders() {
        let decoded = ProviderArchive.decode(["qoder", "codex", "removed-provider"])
        precondition(decoded == Set([.codex, .qoder]))
        precondition(ProviderArchive.encode(decoded) == ["codex", "qoder"])
    }

    private static func cloudSnapshotContainsOnlyDisplayData() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let source = ProviderSnapshot(
            provider: .cursor,
            planName: "Pro",
            metrics: [UsageMetric(
                id: "total",
                title: "套餐总用量",
                usedPercent: 25,
                deadlineAt: fetchedAt.addingTimeInterval(86_400),
                group: .included,
                value: .usd(usedCents: 2500, limitCents: 10_000)
            )],
            fetchedAt: fetchedAt,
            note: "raw-token-must-not-sync",
            subscriptionCategory: .individual
        )
        let snapshot = CloudUsageSnapshot(snapshot: source)
        let data = try snapshot.encoded()
        let encoded = String(decoding: data, as: UTF8.self)
        precondition(!encoded.contains("raw-token-must-not-sync"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(CloudUsageSnapshot.self, from: data)
        precondition(decoded == snapshot)
        precondition(decoded.provider == "cursor")
        precondition(decoded.metrics.first?.usedPercent == 25)
    }

    private static func sharedUsageSnapshotRoundTripsDisplayData() throws {
        let snapshot = SharedUsageSnapshot(
            providers: [
                SharedUsageProvider(
                    id: "codex",
                    title: "Codex",
                    planName: "Pro",
                    metricTitle: "5 小时额度",
                    remainingPercent: 64,
                    isStale: false,
                    metrics: [
                        SharedUsageMetric(
                            id: "weekly",
                            title: "周额度",
                            groupTitle: "套餐额度",
                            usedPercent: 36,
                            remainingPercent: 64,
                            deadlineText: "4 天后重置",
                            valueText: nil,
                            suggestedUsedPercent: 43,
                            showsProgress: true,
                            isPrimary: true
                        ),
                        SharedUsageMetric(
                            id: "session",
                            title: "5 小时额度",
                            groupTitle: "套餐额度",
                            usedPercent: 18,
                            remainingPercent: 82,
                            deadlineText: "2 小时后重置",
                            valueText: nil,
                            suggestedUsedPercent: 40,
                            showsProgress: true,
                            isPrimary: false
                        )
                    ]
                ),
                SharedUsageProvider(
                    id: "cursor",
                    title: "Cursor",
                    planName: nil,
                    metricTitle: "套餐内用量",
                    remainingPercent: 38,
                    isStale: true
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000),
            isRefreshing: false
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SharedUsageSnapshot.self, from: data)
        precondition(decoded == snapshot)
        precondition(decoded.lowestRemainingPercent == 38)
        precondition(decoded.providers[0].primaryMetric?.title == "周额度")
        precondition(decoded.providers[0].primaryMetric?.usedPercent == 36)
        precondition(decoded.providers[0].primaryMetric?.deadlineText == "4 天后重置")
        precondition(decoded.providers[0].displayMetrics.map(\.id) == [
            "weekly", "session"
        ])
        let encoded = String(decoding: data, as: UTF8.self)
        precondition(!encoded.localizedCaseInsensitiveContains("token"))
        precondition(!encoded.localizedCaseInsensitiveContains("cookie"))
    }

    private static func sharedUsageSnapshotResolvesLocalWidgetContainer() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let url = SharedUsageSnapshotStore.localWidgetContainerSnapshotURL(
            homeDirectory: homeDirectory,
            hostBundleIdentifier: "com.example.CodeUsage"
        )
        precondition(url?.path == "/Users/example/Library/Containers/com.example.CodeUsage.widgets/Data/Library/Application Support/CodeUsage/widget-snapshot-v1.json")
        precondition(SharedUsageSnapshotStore.localWidgetContainerSnapshotURL(
            homeDirectory: homeDirectory,
            hostBundleIdentifier: "com.example.CodeUsage.widgets"
        ) == nil)
        precondition(SharedUsageSnapshotStore.localWidgetContainerSnapshotURL(
            homeDirectory: homeDirectory,
            hostBundleIdentifier: nil
        ) == nil)
    }

    private static func sharedUsageSnapshotMirrorsLocalWidgetAlongsideAppGroup() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let groupContainerURL = homeDirectory
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent("group.com.example.CodeUsage", isDirectory: true)
        let urls = SharedUsageSnapshotStore.resolvedWritableSnapshotURLs(
            homeDirectory: homeDirectory,
            groupContainerURL: groupContainerURL,
            hostBundleIdentifier: "com.example.CodeUsage",
            localFallbackEnabled: true
        )
        precondition(urls.contains(
            groupContainerURL.appendingPathComponent("widget-snapshot-v1.json")
        ))
        precondition(urls.contains(URL(fileURLWithPath: "/Users/example/Library/Containers/com.example.CodeUsage.widgets/Data/Library/Application Support/CodeUsage/widget-snapshot-v1.json")))
    }

    private static func sharedUsageSnapshotReadsHostSupportFromSandbox() {
        let sandboxHome = URL(
            fileURLWithPath: "/Users/example/Library/Containers/com.example.CodeUsage.widgets/Data",
            isDirectory: true
        )
        let accountHome = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let urls = SharedUsageSnapshotStore.resolvedReadableSnapshotURLs(
            homeDirectory: sandboxHome,
            userAccountHomeDirectory: accountHome,
            groupContainerURL: nil,
            localFallbackEnabled: true
        )
        precondition(urls.first?.path == "/Users/example/Library/Containers/com.example.CodeUsage.widgets/Data/Library/Application Support/CodeUsage/widget-snapshot-v1.json")
        precondition(urls.contains(URL(fileURLWithPath: "/Users/example/Library/Containers/com.example.CodeUsage.widgets/Data/Library/Application Support/CodeUsage/widget-snapshot-v1.json")))
        precondition(urls.contains(URL(fileURLWithPath: "/Users/example/Library/Application Support/CodeUsage/widget-snapshot-v1.json")))
    }

    private static func sharedUsageSnapshotUsesOnlyAppGroupInProduction() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let groupContainerURL = homeDirectory
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent("group.com.example.CodeUsage", isDirectory: true)
        let readURLs = SharedUsageSnapshotStore.resolvedReadableSnapshotURLs(
            homeDirectory: homeDirectory,
            userAccountHomeDirectory: homeDirectory,
            groupContainerURL: groupContainerURL,
            localFallbackEnabled: false
        )
        let writeURLs = SharedUsageSnapshotStore.resolvedWritableSnapshotURLs(
            homeDirectory: homeDirectory,
            groupContainerURL: groupContainerURL,
            hostBundleIdentifier: "com.example.CodeUsage",
            localFallbackEnabled: false
        )
        let expected = [groupContainerURL.appendingPathComponent(
            "widget-snapshot-v1.json"
        )]
        precondition(readURLs == expected)
        precondition(writeURLs == expected)
    }

    private static func cursorMapsReportedMetrics() throws {
        let usage = """
        {
          "enabled": true,
          "billingCycleStart": "2029-12-01T00:00:00Z",
          "billingCycleEnd": "2030-01-01T00:00:00Z",
          "planUsage": {
            "totalPercentUsed": 23.5,
            "autoPercentUsed": 10,
            "apiPercentUsed": 31
          }
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(usageData: usage)
        precondition(snapshot.metrics.map(\.id) == ["total", "auto", "api"])
        precondition(snapshot.metrics[0].usedPercent == 23.5)
        precondition(snapshot.metrics[0].windowDuration == 31 * 24 * 60 * 60)
        precondition(snapshot.metrics.allSatisfy { $0.group == .included })
    }

    private static func cursorPreservesOriginalBillingFields() throws {
        let usage = """
        {
          "enabled": true,
          "planUsage": {
            "limit": 2000,
            "includedSpend": 2000,
            "totalPercentUsed": 97.225
          },
          "spendLimitUsage": {
            "individualUsed": 350,
            "individualLimit": 1000,
            "limitType": "team"
          }
        }
        """.data(using: .utf8)!
        let summary = """
        {"individualUsage":{"plan":{"used":2000,"limit":2000},
                            "onDemand":{"used":0,"limit":5000}}}
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(
            usageData: usage,
            personalSummaryData: summary
        )
        let total = snapshot.metrics.first { $0.id == "total" }!
        precondition(total.usedPercent == 97.225 && total.value == nil)
        let personal = snapshot.metrics.first { $0.id == "on_demand_personal" }!
        precondition(personal.usedPercent == 35)
        guard case .usd(let used, let limit) = personal.value else {
            preconditionFailure("Expected original personal spend")
        }
        precondition(used == 350 && limit == 1000)
    }

    private static func cursorCalculatesTotalWhenMissing() throws {
        let usage = """
        {
          "enabled": true,
          "billingCycleEnd": "2030-01-01T00:00:00Z",
          "planUsage": {"limit": 10000, "includedSpend": 2500, "totalSpend": 8000}
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(usageData: usage)
        precondition(snapshot.primaryMetric?.usedPercent == 25)
        precondition(snapshot.primaryMetric?.windowDuration == nil)
    }

    private static func cursorUsesPersonalSummaryWhenTeamOmitsIndividualSpend() throws {
        let usage = """
        {
          "enabled": true,
          "planUsage": {
            "limit": 2000,
            "includedSpend": 2000,
            "totalSpend": 7778,
            "totalPercentUsed": 97.225,
            "apiPercentUsed": 97.225
          },
          "spendLimitUsage": {
            "pooledLimit": "45800000",
            "pooledUsed": 1243372,
            "limitType": "team"
          }
        }
        """.data(using: .utf8)!
        let summary = """
        {
          "individualUsage": {
            "plan": {"used": 2000, "limit": 2000, "remaining": 0},
            "onDemand": {"enabled": true, "used": 0, "limit": null}
          }
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(
            usageData: usage,
            personalSummaryData: summary
        )
        let total = snapshot.metrics.first { $0.id == "total" }!
        precondition(total.usedPercent == 100)
        guard case .usd(let includedUsed, let includedLimit) = total.value else {
            preconditionFailure("Expected personal plan amount")
        }
        precondition(includedUsed == 2000 && includedLimit == 2000)
        precondition(snapshot.metrics.contains { $0.id == "auto" } == false)
        precondition(snapshot.metrics.first { $0.id == "api" }?.title == "第三方模型（API）")
        precondition(snapshot.metrics.first { $0.id == "api" }?.usedPercent == 97.225)
        let personal = snapshot.metrics.first { $0.id == "on_demand_personal" }!
        precondition(personal.title == "我的消费")
        precondition(personal.showsProgress == false)
        guard case .usd(let used, let limit) = personal.value else {
            preconditionFailure("Expected personal USD usage")
        }
        precondition(used == 0 && limit == nil)
        precondition(snapshot.metrics.contains { $0.id == "on_demand_team" })
        precondition(snapshot.metrics.first { $0.id == "on_demand_team" }?
            .suggestedUsedPercent() == nil)

        let withoutSummary = try CursorProvider.map(usageData: usage)
        precondition(withoutSummary.metrics.contains { $0.id == "on_demand_personal" } == false)
        precondition(withoutSummary.note != nil)
    }

    private static func cursorMapsOnDemandUsage() throws {
        let usage = """
        {
          "enabled": true,
          "billingCycleStart": "2029-12-01T00:00:00Z",
          "billingCycleEnd": "2030-01-01T00:00:00Z",
          "planUsage": {
            "totalPercentUsed": 28,
            "autoPercentUsed": 14.2,
            "apiPercentUsed": 100
          },
          "spendLimitUsage": {
            "individualUsed": 3020,
            "pooledLimit": 31550000,
            "pooledUsed": 1328490,
            "limitType": "team"
          }
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(
            usageData: usage,
            individualLimitCents: 50_000
        )
        precondition(snapshot.metrics.map(\.id) == [
            "total", "auto", "api", "on_demand_personal", "on_demand_team"
        ])
        let personal = snapshot.metrics[3]
        let team = snapshot.metrics[4]
        precondition(abs(personal.usedPercent - 6.04) < 0.000_001)
        precondition(abs(team.usedPercent - 4.210744849445325) < 0.000_001)
        precondition(personal.group == .onDemand && team.group == .onDemand)
        precondition(personal.title == "我的消费")
        precondition(team.title == "团队总消费")
        precondition(snapshot.subscriptionCategory == .team)
        precondition(personal.allowsLimitEditing)
        precondition(snapshot.primaryMetric?.id == "on_demand_personal")
        precondition(snapshot.widgetPrimaryMetric?.id == "total")
        guard case .usd(let used, let limit) = personal.value else {
            preconditionFailure("Expected personal USD usage")
        }
        precondition(used == 3020 && limit == 50_000)
    }

    private static func cursorPrefersProviderIndividualLimit() throws {
        let usage = """
        {
          "enabled": true,
          "planUsage": {"totalPercentUsed": 28},
          "spendLimitUsage": {"individualUsed": 3020, "individualLimit": 10000}
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(
            usageData: usage,
            individualLimitCents: 50_000
        )
        let personal = snapshot.metrics.first { $0.id == "on_demand_personal" }!
        precondition(abs(personal.usedPercent - 30.2) < 0.000_001)
        precondition(personal.allowsLimitEditing == false)
        guard case .usd(_, let limit) = personal.value else {
            preconditionFailure("Expected personal USD usage")
        }
        precondition(limit == 10_000)
    }

    private static func cursorKeepsSpendWithoutIndividualLimit() throws {
        let usage = """
        {
          "enabled": true,
          "planUsage": {"totalPercentUsed": 28},
          "spendLimitUsage": {"individualUsed": 3020}
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(usageData: usage)
        let personal = snapshot.metrics.first { $0.id == "on_demand_personal" }!
        precondition(personal.showsProgress == false)
        precondition(personal.allowsLimitEditing)
        precondition(snapshot.primaryMetric?.id == "total")
    }

    private static func cursorMapsSpendWithoutPlanUsage() throws {
        let usage = """
        {
          "enabled": true,
          "billingCycleEnd": "2030-01-01T00:00:00Z",
          "spendLimitUsage": {
            "individualUsed": 3020,
            "individualLimit": 10000,
            "pooledUsed": 125000,
            "pooledLimit": 500000
          }
        }
        """.data(using: .utf8)!
        let snapshot = try CursorProvider.map(usageData: usage)
        precondition(snapshot.metrics.map(\.id) == [
            "on_demand_personal", "on_demand_team"
        ])
        precondition(abs(snapshot.metrics[0].usedPercent - 30.2) < 0.000_001)
        precondition(snapshot.metrics[1].usedPercent == 25)
        precondition(snapshot.primaryMetric?.id == "on_demand_personal")
        precondition(snapshot.widgetPrimaryMetric?.id == "on_demand_personal")
    }

    private static func cursorLabelsPersonalAndTeamUsage() throws {
        let personalUsage = """
        {
          "enabled": true,
          "planUsage": {"totalPercentUsed": 28},
          "spendLimitUsage": {
            "individualUsed": 1240,
            "individualLimit": 5000,
            "limitType": "individual"
          }
        }
        """.data(using: .utf8)!
        let personalPlan = """
        {"planInfo":{"planName":"Pro"}}
        """.data(using: .utf8)!
        let personal = try CursorProvider.map(
            usageData: personalUsage,
            planData: personalPlan
        )
        precondition(personal.subscriptionCategory == .individual)
        precondition(
            personal.metrics.first { $0.id == "on_demand_personal" }?.title
                == "本期消费"
        )
        precondition(personal.metrics.contains { $0.id == "on_demand_team" } == false)

        let enterpriseUsage = """
        {
          "enabled": true,
          "planUsage": {"totalPercentUsed": 20},
          "spendLimitUsage": {
            "individualUsed": 1000,
            "individualLimit": 10000,
            "pooledUsed": 30000,
            "pooledLimit": 100000,
            "limitType": "team"
          }
        }
        """.data(using: .utf8)!
        let enterprisePlan = """
        {"planInfo":{"planName":"Enterprise"}}
        """.data(using: .utf8)!
        let enterprise = try CursorProvider.map(
            usageData: enterpriseUsage,
            planData: enterprisePlan
        )
        precondition(enterprise.subscriptionCategory == .enterprise)
        precondition(
            enterprise.metrics.first { $0.id == "on_demand_personal" }?.title
                == "我的消费"
        )
        precondition(
            enterprise.metrics.first { $0.id == "on_demand_team" }?.title
                == "组织总消费"
        )
    }

    private static func subscriptionSimulationBuildsFourCategories() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for category in [
            SubscriptionCategory.freeTrial,
            .individual,
            .team,
            .enterprise
        ] {
            let states = SubscriptionSimulation.states(for: category, now: now)
            precondition(states.count == ProviderKind.allCases.count)
            precondition(states.values.allSatisfy {
                $0.snapshot?.subscriptionCategory == category
            })
        }

        let personalCursor = SubscriptionSimulation.states(
            for: .individual,
            now: now
        )[.cursor]?.snapshot
        precondition(personalCursor?.metrics.contains {
            $0.id == "on_demand_personal" && $0.title == "本期消费"
        } == true)
        precondition(personalCursor?.metrics.contains {
            $0.id == "on_demand_team"
        } == false)

        let teamCursor = SubscriptionSimulation.states(
            for: .team,
            now: now
        )[.cursor]?.snapshot
        precondition(teamCursor?.metrics.contains {
            $0.id == "on_demand_personal" && $0.title == "我的消费"
        } == true)
        precondition(teamCursor?.metrics.contains {
            $0.id == "on_demand_team" && $0.title == "团队总消费"
        } == true)

        precondition(SubscriptionSimulation.launchCategory(
            arguments: ["CodeUsage", "--subscription-simulation", "--subscription=team"],
            environment: [:]
        ) == .team)
        precondition(SubscriptionSimulation.launchCategory(
            arguments: ["CodeUsage"],
            environment: [:]
        ) == nil)
    }

    private static func claudeMapsWeeklyAndSessionWindows() throws {
        let usage = """
        {
          "seven_day": {
            "utilization": 37.5,
            "resets_at": "2030-01-07T00:00:00Z"
          },
          "five_hour": {
            "utilization": 12,
            "resets_at": "2030-01-01T05:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let snapshot = try ClaudeCodeProvider.map(usageData: usage)
        precondition(snapshot.provider == .claude)
        precondition(snapshot.metrics.map(\.id) == ["weekly", "session"])
        precondition(snapshot.primaryMetric?.usedPercent == 37.5)
        precondition(snapshot.metrics[0].windowDuration == 7 * 24 * 60 * 60)
        precondition(snapshot.metrics[1].windowDuration == 5 * 60 * 60)
    }

    private static func kiroMapsPreciseCreditsAndExtras() throws {
        let usage = """
        {
          "nextDateReset": "2030-02-01T00:00:00Z",
          "subscriptionInfo": {"subscriptionTitle": "KIRO PRO+"},
          "usageBreakdownList": [
            {
              "resourceType": "AGENTIC_REQUEST",
              "displayNamePlural": "credits",
              "currentUsage": 123,
              "currentUsageWithPrecision": 123.45,
              "usageLimit": 1000,
              "usageLimitWithPrecision": 1000,
              "bonuses": [
                {"status": "ACTIVE", "currentUsage": 10, "usageLimit": 50}
              ],
              "overageCredits": [
                {"currentUsage": 5, "usageLimit": 100}
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let snapshot = try KiroProvider.map(usageData: usage)
        precondition(snapshot.provider == .kiro)
        precondition(snapshot.planName == "Pro+")
        precondition(snapshot.metrics.map(\.id) == ["credits", "add_on"])
        precondition(abs((snapshot.primaryMetric?.usedPercent ?? -1) - 12.345) < 0.0001)
        precondition(snapshot.primaryMetric?.windowDuration == 31 * 24 * 60 * 60)
        precondition(snapshot.note?.contains("Bonus 剩余 40") == true)
        precondition(snapshot.metrics[1].group == .personalAddOn)
        guard case .quantity(let used, let limit, _, _) = snapshot.metrics[1].value else {
            preconditionFailure("Expected Kiro Add-on quantity")
        }
        precondition(used == 5 && limit == 100)
    }

    private static func kiroParsesCLIAuthRows() {
        let output = "kirocli:social:token|7B226163636573735F746F6B656E223A2274227D\n"
        let rows = KiroProvider.parseCLIAuthRows(output)
        precondition(rows.count == 1)
        precondition(rows[0].key == "kirocli:social:token")
        let object = try? JSONSerialization.jsonObject(with: rows[0].data) as? [String: String]
        precondition(object?["access_token"] == "t")
    }

    private static func kiroMergesRefreshedIDECredential() throws {
        let original = """
        {
          "accessToken": "old-access",
          "refreshToken": "old-refresh",
          "expiresAt": "2020-01-01T00:00:00Z",
          "profileArn": "old-profile",
          "provider": "Google",
          "authMethod": "social"
        }
        """.data(using: .utf8)!
        let response = """
        {
          "accessToken": "new-access",
          "refreshToken": "new-refresh",
          "profileArn": "new-profile",
          "expiresIn": 3600
        }
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let mergedData = try KiroProvider.mergedRefreshedCredentialData(
            originalData: original,
            responseData: response,
            now: now
        )
        let merged = try JSONSerialization.jsonObject(with: mergedData) as! [String: Any]
        precondition(merged["accessToken"] as? String == "new-access")
        precondition(merged["refreshToken"] as? String == "new-refresh")
        precondition(merged["profileArn"] as? String == "new-profile")
        precondition(merged["provider"] as? String == "Google")
        let expiry = DateParsing.date(from: merged["expiresAt"])
        precondition(expiry == now.addingTimeInterval(3600))
    }

    private static func kiroMergesRefreshedCLICredential() throws {
        let original = """
        {
          "access_token": "old-access",
          "refresh_token": "keep-refresh",
          "expires_at": "2020-01-01T00:00:00Z",
          "profile_arn": "profile",
          "provider": "google"
        }
        """.data(using: .utf8)!
        let response = """
        {
          "accessToken": "new-access",
          "expiresIn": "1800"
        }
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let mergedData = try KiroProvider.mergedRefreshedCredentialData(
            originalData: original,
            responseData: response,
            now: now
        )
        let merged = try JSONSerialization.jsonObject(with: mergedData) as! [String: Any]
        precondition(merged["access_token"] as? String == "new-access")
        precondition(merged["refresh_token"] as? String == "keep-refresh")
        precondition(merged["accessToken"] == nil)
        let expiry = DateParsing.date(from: merged["expires_at"])
        precondition(expiry == now.addingTimeInterval(1800))
    }

    private static func kiroRejectsMalformedRefreshResponse() throws {
        let original = """
        {"accessToken":"old","refreshToken":"refresh","expiresAt":"2020-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let response = """
        {"accessToken":"new"}
        """.data(using: .utf8)!
        do {
            _ = try KiroProvider.mergedRefreshedCredentialData(
                originalData: original,
                responseData: response
            )
            preconditionFailure("Kiro malformed refresh response should fail")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                preconditionFailure("Unexpected Kiro refresh error: \(error)")
            }
        }
    }

    private static func kiroFallsBackToLegacyLimits() throws {
        let usage = """
        {
          "nextDateReset": 1896134400,
          "subscriptionInfo": {"subscriptionTitle": "Kiro Free"},
          "limits": [
            {"type": "CODE_COMPLETIONS", "currentUsage": 90, "totalUsageLimit": 100},
            {"type": "AGENTIC_REQUEST", "currentUsage": 12, "totalUsageLimit": 50, "percentUsed": 24}
          ]
        }
        """.data(using: .utf8)!
        let snapshot = try KiroProvider.map(usageData: usage)
        precondition(snapshot.planName == "Free")
        precondition(snapshot.primaryMetric?.usedPercent == 24)
        guard case .quantity(let used, let limit, _, _) = snapshot.primaryMetric?.value else {
            preconditionFailure("Expected Kiro credits quantity")
        }
        precondition(used == 12 && limit == 50)
    }

    private static func kiroRejectsMissingQuota() throws {
        let usage = "{\"subscriptionInfo\":{\"subscriptionTitle\":\"Kiro Pro\"}}"
            .data(using: .utf8)!
        do {
            _ = try KiroProvider.map(usageData: usage)
            preconditionFailure("Kiro missing quota should fail")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                preconditionFailure("Unexpected Kiro error: \(error)")
            }
        }
    }

    private static func qoderMapsPlanAddOnAndSharedCredits() throws {
        let snapshot = try QoderProvider.map(usageObject: [
            "userType": "teams",
            "expiresAt": 1_893_456_000_000 as Double,
            "userQuota": [
                "total": 2_000,
                "used": 500,
                "remaining": 1_500,
                "percentage": 0.25,
                "unit": "credits"
            ],
            "addOnQuota": [
                "total": 1_500,
                "used": 150,
                "remaining": 1_350,
                "percentage": 0.10,
                "unit": "credits"
            ],
            "orgResourcePackage": [
                "cap": 2_000,
                "used": 10,
                "remaining": 1_990,
                "percentage": 0.005,
                "available": true,
                "unit": "credits"
            ]
        ], planObject: [
            "plan_tier_name": "Teams"
        ], percentageRepresentation: .ratio)
        precondition(snapshot.provider == .qoder)
        precondition(snapshot.planName == "Teams")
        precondition(snapshot.metrics.map(\.id) == ["included", "add_on", "shared"])
        precondition(snapshot.metrics.map(\.group) == [
            .included, .personalAddOn, .organizationShared
        ])
        precondition(snapshot.metrics[0].usedPercent == 25)
        precondition(snapshot.metrics[0].deadlineKind == .expiration)
        guard let qoderDeadline = snapshot.metrics[0].deadlineAt else {
            preconditionFailure("Expected Qoder Credits expiration")
        }
        precondition(snapshot.metrics[0].deadlineDescription(
            at: qoderDeadline.addingTimeInterval(-24 * 60 * 60)
        ) == "1 天后到期")
        precondition(snapshot.metrics[1].usedPercent == 10)
        precondition(snapshot.metrics[2].usedPercent == 0.5)
        precondition(snapshot.primaryMetric?.id == "included")
        guard case .quantity(let used, let limit, _, let unit) = snapshot.metrics[2].value else {
            preconditionFailure("Expected Qoder shared Credits quantity")
        }
        precondition(used == 10 && limit == 2_000 && unit == "credits")
    }

    private static func qoderPreservesCLISmallPercentages() throws {
        let halfPercent = try QoderProvider.map(usageObject: [
            "userQuota": [
                "total": 10_000,
                "used": 50,
                "remaining": 9_950,
                "percentage": 0.5,
                "unit": "credits"
            ]
        ], percentageRepresentation: .percent)
        precondition(halfPercent.primaryMetric?.usedPercent == 0.5)

        let onePercent = try QoderProvider.map(usageObject: [
            "userQuota": [
                "total": 10_000,
                "used": 100,
                "remaining": 9_900,
                "percentage": 1,
                "unit": "credits"
            ]
        ], percentageRepresentation: .percent)
        precondition(onePercent.primaryMetric?.usedPercent == 1)
    }

    private static func qoderRejectsNotificationFlood() throws {
        var descriptors: [Int32] = [-1, -1]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer {
            Darwin.close(descriptors[0])
            Darwin.close(descriptors[1])
        }

        var flood = Data()
        for index in 0..<32 {
            let body = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "method": "test/notification/\(index)"
            ])
            flood.append(Data("Content-Length: \(body.count)\r\n\r\n".utf8))
            flood.append(body)
        }
        let written = flood.withUnsafeBytes { rawBuffer in
            Darwin.write(descriptors[1], rawBuffer.baseAddress, rawBuffer.count)
        }
        precondition(written == flood.count)

        do {
            _ = try QoderProvider.sendIDERequest(
                descriptor: descriptors[0],
                id: 99,
                method: "credit/usage",
                params: nil
            )
            preconditionFailure("Qoder notification flood should be rejected")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                preconditionFailure("Unexpected Qoder notification flood error: \(error)")
            }
        }
    }

    private static func qoderRejectsUnsafeDiscoveryPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeusage-qoder-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let info = directory.appendingPathComponent(".info.json")
        let socket = directory.appendingPathComponent("qoder.sock")
        let payload = try JSONSerialization.data(withJSONObject: [
            "ipcServerPath": socket.path
        ])
        try payload.write(to: info)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: info.path)

        do {
            _ = try QoderProvider.validatedIDESocketPath(
                infoFile: info.path,
                expectedDirectory: directory.path
            )
            preconditionFailure("World-writable Qoder discovery file should be rejected")
        } catch let error as UsageError {
            guard case .invalidResponse = error else {
                preconditionFailure("Unexpected Qoder discovery error: \(error)")
            }
        }
    }

    private static func qoderInstallationRecognizesOverrides() {
        let explicitCLI = "/private/tmp/codeusage-test-qodercli"
        precondition(ProviderInstallation.isQoderInstalled(
            environment: ["QODERCLI_PATH": explicitCLI],
            fileExists: { _ in false },
            isExecutable: { $0 == explicitCLI }
        ))

        let cliHome = "/private/tmp/codeusage-test-qoder-home"
        precondition(ProviderInstallation.isQoderInstalled(
            environment: ["QODER_CLI_HOME": cliHome],
            fileExists: { _ in false },
            isExecutable: { $0 == "\(cliHome)/.qoder/local/qoder" }
        ))

        precondition(ProviderInstallation.isQoderInstalled(
            environment: [:],
            fileExists: {
                $0.hasSuffix("/Library/Application Support/Qoder/SharedClientCache/.info.json")
            },
            isExecutable: { _ in false }
        ))
    }

    private static func qoderBinarySelectionRejectsExecutableDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeusage-qoder-binary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let misleadingDirectory = directory.appendingPathComponent("qodercli", isDirectory: true)
        try FileManager.default.createDirectory(
            at: misleadingDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let executable = directory.appendingPathComponent("qodercli-1.1.31", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let symlink = directory.appendingPathComponent("qodercli-link", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            atPath: symlink.path,
            withDestinationPath: executable.path
        )

        precondition(!ProcessUtils.isExecutableRegularFile(atPath: misleadingDirectory.path))
        precondition(ProcessUtils.isExecutableRegularFile(atPath: symlink.path))
        precondition(QoderProvider.firstExecutableBinary(in: [
            misleadingDirectory.path,
            symlink.path
        ]) == symlink.path)
    }

    private static func suggestedUsageTracksElapsedWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let metric = UsageMetric(
            id: "weekly",
            title: "周额度",
            usedPercent: 35,
            deadlineAt: now.addingTimeInterval(7 * 24 * 60 * 60),
            windowDuration: 7 * 24 * 60 * 60
        )
        let suggested = metric.suggestedUsedPercent(at: now)
        precondition(abs((suggested ?? -1) - (100.0 / 7.0)) < 0.001)
        precondition(metric.deadlineDescription(at: now) == "7 天后重置")

        let endOfFirstDay = metric.suggestedUsedPercent(
            at: now.addingTimeInterval(24 * 60 * 60 - 1)
        )
        precondition(abs((endOfFirstDay ?? -1) - (100.0 / 7.0)) < 0.001)

        let secondDay = metric.suggestedUsedPercent(
            at: now.addingTimeInterval(24 * 60 * 60)
        )
        precondition(abs((secondDay ?? -1) - (200.0 / 7.0)) < 0.001)

        let beforeWindow = metric.suggestedUsedPercent(
            at: now.addingTimeInterval(-1)
        )
        precondition(beforeWindow == 0)

        let expired = metric.suggestedUsedPercent(
            at: now.addingTimeInterval(7 * 24 * 60 * 60)
        )
        precondition(expired == 100)

        let session = UsageMetric(
            id: "session",
            title: "5 小时会话",
            usedPercent: 10,
            deadlineAt: now.addingTimeInterval(4.75 * 60 * 60),
            windowDuration: 5 * 60 * 60
        )
        precondition(session.suggestedUsedPercent(at: now) == 20)

        let dstMonth = UsageMetric(
            id: "total",
            title: "总用量",
            usedPercent: 0,
            deadlineAt: now.addingTimeInterval(30 * 24 * 60 * 60 + 60 * 60),
            windowDuration: 30 * 24 * 60 * 60 + 60 * 60
        )
        let firstDay = dstMonth.suggestedUsedPercent(at: now)
        precondition(abs((firstDay ?? -1) - (100.0 / 30.0)) < 0.001)
    }
}

private final class CursorCredentialFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CursorStoredAuth
    private var reads = 0
    private var denied = false
    private var storedReadDenied = false

    init(_ stored: CursorStoredAuth) { self.stored = stored }
    func read() throws -> CursorStoredAuth {
        lock.lock(); defer { lock.unlock() }
        if storedReadDenied { throw UsageError.requestFailed("Database temporarily unavailable") }
        return stored
    }
    func set(_ value: CursorStoredAuth) { lock.lock(); defer { lock.unlock() }; stored = value }
    var passwordReads: Int { lock.lock(); defer { lock.unlock() }; return reads }
    var denyPassword: Bool {
        get { lock.lock(); defer { lock.unlock() }; return denied }
        set { lock.lock(); defer { lock.unlock() }; denied = newValue }
    }
    var denyStoredRead: Bool {
        get { lock.lock(); defer { lock.unlock() }; return storedReadDenied }
        set { lock.lock(); defer { lock.unlock() }; storedReadDenied = newValue }
    }
    func password() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        if denied { throw UsageError.requestFailed("Keychain access denied by test") }
        return Data("fixture-password".utf8)
    }
}
