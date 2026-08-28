import Darwin
import Foundation

@main
struct SelfTest {
    static func main() throws {
        try codexSelectsWeeklyWindow()
        try codexMapsWorkspaceLimits()
        usageErrorsIdentifySignInFailures()
        codexIdentifiesSignInFailures()
        providerArchiveRoundTripsKnownProviders()
        try cloudSnapshotContainsOnlyDisplayData()
        try cursorMapsReportedMetrics()
        try cursorCalculatesTotalWhenMissing()
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
        subscriptionSimulationBuildsFourCategories()
        suggestedUsageTracksElapsedWindow()
        print("CodeUsage mapper tests passed")
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
