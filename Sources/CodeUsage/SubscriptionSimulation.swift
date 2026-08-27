import Foundation

enum SubscriptionSimulation {
    static let launchFlag = "--subscription-simulation"
    static let environmentKey = "CODEUSAGE_SUBSCRIPTION_SIMULATION"

    static func launchCategory(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SubscriptionCategory? {
        let environmentValue = environment[environmentKey]?.lowercased()
        let isEnabled = arguments.contains(launchFlag) ||
            environmentValue == "1" ||
            environmentValue == "true"
        guard isEnabled else { return nil }

        if let rawValue = arguments.first(where: { $0.hasPrefix("--subscription=") })?
            .split(separator: "=", maxSplits: 1)
            .last {
            return category(from: String(rawValue)) ?? .freeTrial
        }
        if let environmentValue,
           environmentValue != "1",
           environmentValue != "true" {
            return category(from: environmentValue) ?? .freeTrial
        }
        return .freeTrial
    }

    static func states(
        for category: SubscriptionCategory,
        now: Date = Date()
    ) -> [ProviderKind: ProviderDisplayState] {
        let normalized = category == .unknown ? SubscriptionCategory.freeTrial : category
        let snapshots: [ProviderSnapshot]
        switch normalized {
        case .freeTrial:
            snapshots = freeTrialSnapshots(now: now)
        case .individual:
            snapshots = individualSnapshots(now: now)
        case .team:
            snapshots = teamSnapshots(now: now)
        case .enterprise:
            snapshots = enterpriseSnapshots(now: now)
        case .unknown:
            snapshots = []
        }
        return Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.provider, ProviderDisplayState(snapshot: $0))
        })
    }

    private static func category(from value: String) -> SubscriptionCategory? {
        switch value.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "free", "trial", "free-trial": return .freeTrial
        case "individual", "personal": return .individual
        case "team", "business": return .team
        case "enterprise", "organization", "organisation": return .enterprise
        default: return nil
        }
    }

    private static func freeTrialSnapshots(now: Date) -> [ProviderSnapshot] {
        [
            snapshot(
                .codex,
                plan: "Free",
                category: .freeTrial,
                now: now,
                metrics: [
                    percentage(
                        id: "session",
                        title: "5 小时额度",
                        used: 24,
                        reset: now.addingTimeInterval(3 * 60 * 60),
                        duration: 5 * 60 * 60,
                        group: .included
                    ),
                    percentage(
                        id: "weekly",
                        title: "7 天额度",
                        used: 12,
                        reset: now.addingTimeInterval(6 * 24 * 60 * 60),
                        duration: 7 * 24 * 60 * 60,
                        group: .included
                    )
                ],
                note: "仅显示服务端实际返回的免费额度窗口"
            ),
            snapshot(
                .cursor,
                plan: "Hobby",
                category: .freeTrial,
                now: now,
                metrics: cursorIncludedMetrics(
                    total: 32,
                    auto: 18,
                    api: 14,
                    reset: now.addingTimeInterval(12 * 24 * 60 * 60),
                    duration: 14 * 24 * 60 * 60
                ),
                note: "免费方案只显示接口实际返回的有限用量，不硬编码额度"
            ),
            snapshot(
                .claude,
                plan: "Free",
                category: .freeTrial,
                now: now,
                metrics: [],
                note: "当前免费账号不包含可读取的 Claude Code 套餐额度"
            ),
            snapshot(
                .kiro,
                plan: "Free",
                category: .freeTrial,
                now: now,
                metrics: [
                    credits(
                        id: "credits",
                        title: "月度 Credits",
                        used: 18,
                        limit: 50,
                        reset: now.addingTimeInterval(12 * 24 * 60 * 60),
                        duration: 30 * 24 * 60 * 60,
                        group: .included
                    )
                ]
            ),
            snapshot(
                .qoder,
                plan: "Free Trial",
                category: .freeTrial,
                now: now,
                metrics: [
                    credits(
                        id: "included",
                        title: "试用 Credits",
                        used: 2,
                        limit: 300,
                        reset: now.addingTimeInterval(13 * 24 * 60 * 60),
                        duration: 14 * 24 * 60 * 60,
                        group: .included,
                        deadlineKind: .expiration
                    )
                ]
            )
        ]
    }

    private static func individualSnapshots(now: Date) -> [ProviderSnapshot] {
        let monthlyReset = now.addingTimeInterval(24 * 24 * 60 * 60)
        return [
            snapshot(
                .codex,
                plan: "Pro",
                category: .individual,
                now: now,
                metrics: [
                    percentage(
                        id: "session",
                        title: "5 小时额度",
                        used: 16,
                        reset: now.addingTimeInterval(3 * 60 * 60),
                        duration: 5 * 60 * 60,
                        group: .included
                    ),
                    percentage(
                        id: "weekly",
                        title: "7 天额度",
                        used: 29,
                        reset: now.addingTimeInterval(6 * 24 * 60 * 60),
                        duration: 7 * 24 * 60 * 60,
                        group: .included
                    )
                ]
            ),
            snapshot(
                .cursor,
                plan: "Pro",
                category: .individual,
                now: now,
                metrics: cursorIncludedMetrics(
                    total: 32,
                    auto: 19,
                    api: 73,
                    reset: monthlyReset,
                    duration: 30 * 24 * 60 * 60
                ) + [
                    UsageMetric(
                        id: "on_demand_personal",
                        title: "本期消费",
                        usedPercent: 27.15,
                        deadlineAt: monthlyReset,
                        windowDuration: 30 * 24 * 60 * 60,
                        group: .onDemand,
                        value: .usd(usedCents: 13_575, limitCents: 50_000)
                    )
                ]
            ),
            snapshot(
                .claude,
                plan: "Max 5x",
                category: .individual,
                now: now,
                metrics: [
                    percentage(
                        id: "session",
                        title: "5 小时会话",
                        used: 32,
                        reset: now.addingTimeInterval(2 * 60 * 60),
                        duration: 5 * 60 * 60,
                        group: .included
                    ),
                    percentage(
                        id: "weekly",
                        title: "周额度",
                        used: 26,
                        reset: now.addingTimeInterval(5 * 24 * 60 * 60),
                        duration: 7 * 24 * 60 * 60,
                        group: .included
                    )
                ],
                note: "Claude 与 Claude Code 共用套餐额度"
            ),
            snapshot(
                .kiro,
                plan: "Pro",
                category: .individual,
                now: now,
                metrics: [
                    credits(
                        id: "credits",
                        title: "月度 Credits",
                        used: 420,
                        limit: 1_000,
                        reset: monthlyReset,
                        duration: 30 * 24 * 60 * 60,
                        group: .included
                    ),
                    credits(
                        id: "add_on",
                        title: "加购 Credits",
                        used: 25,
                        limit: 125,
                        reset: nil,
                        duration: nil,
                        group: .personalAddOn
                    )
                ]
            ),
            snapshot(
                .qoder,
                plan: "Personal Professional",
                category: .individual,
                now: now,
                metrics: [
                    credits(
                        id: "included",
                        title: "套餐 Credits",
                        used: 620,
                        limit: 2_000,
                        reset: monthlyReset,
                        duration: 30 * 24 * 60 * 60,
                        group: .included,
                        deadlineKind: .expiration
                    ),
                    credits(
                        id: "add_on",
                        title: "加购 Credits",
                        used: 150,
                        limit: 1_500,
                        reset: nil,
                        duration: nil,
                        group: .personalAddOn
                    )
                ]
            )
        ]
    }

    private static func teamSnapshots(now: Date) -> [ProviderSnapshot] {
        let monthlyReset = now.addingTimeInterval(24 * 24 * 60 * 60)
        return [
            snapshot(
                .codex,
                plan: "Business",
                category: .team,
                now: now,
                metrics: [
                    percentage(
                        id: "session",
                        title: "5 小时额度",
                        used: 18,
                        reset: now.addingTimeInterval(3 * 60 * 60),
                        duration: 5 * 60 * 60,
                        group: .included
                    ),
                    percentage(
                        id: "weekly",
                        title: "7 天额度",
                        used: 31,
                        reset: now.addingTimeInterval(5 * 24 * 60 * 60),
                        duration: 7 * 24 * 60 * 60,
                        group: .included
                    ),
                    credits(
                        id: "individual_limit",
                        title: "个人使用上限",
                        used: 1_200,
                        limit: 5_000,
                        reset: monthlyReset,
                        duration: 30 * 24 * 60 * 60,
                        group: .credits
                    ),
                    remainingCredits(
                        id: "workspace_credits",
                        title: "工作区余额",
                        remaining: 4_280,
                        group: .credits
                    )
                ],
                note: "只显示当前成员可读取的额度，不推算整个工作区消费"
            ),
            snapshot(
                .cursor,
                plan: "Team Standard",
                category: .team,
                now: now,
                metrics: cursorIncludedMetrics(
                    total: 34,
                    auto: 21,
                    api: 61,
                    reset: monthlyReset,
                    duration: 30 * 24 * 60 * 60
                ) + [
                    UsageMetric(
                        id: "on_demand_personal",
                        title: "我的消费",
                        usedPercent: 27.15,
                        deadlineAt: monthlyReset,
                        windowDuration: 30 * 24 * 60 * 60,
                        group: .onDemand,
                        value: .usd(usedCents: 13_575, limitCents: 50_000)
                    ),
                    UsageMetric(
                        id: "on_demand_team",
                        title: "团队总消费",
                        usedPercent: 5.13,
                        deadlineAt: monthlyReset,
                        windowDuration: 30 * 24 * 60 * 60,
                        group: .onDemand,
                        value: .usd(usedCents: 1_626_392, limitCents: 31_700_000)
                    )
                ]
            ),
            snapshot(
                .claude,
                plan: "Team Premium",
                category: .team,
                now: now,
                metrics: [
                    percentage(
                        id: "session",
                        title: "5 小时会话",
                        used: 28,
                        reset: now.addingTimeInterval(2 * 60 * 60),
                        duration: 5 * 60 * 60,
                        group: .included
                    ),
                    percentage(
                        id: "weekly",
                        title: "周额度",
                        used: 24,
                        reset: now.addingTimeInterval(5 * 24 * 60 * 60),
                        duration: 7 * 24 * 60 * 60,
                        group: .included
                    )
                ],
                note: "显示当前成员额度；组织统计需要管理员权限"
            ),
            snapshot(
                .kiro,
                plan: "Pro（组织成员）",
                category: .team,
                now: now,
                metrics: [
                    credits(
                        id: "credits",
                        title: "我的月度 Credits",
                        used: 360,
                        limit: 1_000,
                        reset: monthlyReset,
                        duration: 30 * 24 * 60 * 60,
                        group: .included
                    )
                ],
                note: "Kiro 未提供团队共享 Credits；这里只显示当前成员"
            ),
            snapshot(
                .qoder,
                plan: "Teams",
                category: .team,
                now: now,
                metrics: [
                    credits(
                        id: "included",
                        title: "我的套餐 Credits",
                        used: 860,
                        limit: 3_000,
                        reset: monthlyReset,
                        duration: 30 * 24 * 60 * 60,
                        group: .included,
                        deadlineKind: .expiration
                    ),
                    credits(
                        id: "add_on",
                        title: "加购 Credits",
                        used: 120,
                        limit: 1_500,
                        reset: nil,
                        duration: nil,
                        group: .personalAddOn
                    ),
                    credits(
                        id: "shared",
                        title: "组织共享 Credits",
                        used: 220,
                        limit: 1_000,
                        reset: nil,
                        duration: nil,
                        group: .organizationShared
                    )
                ],
                note: "共享额度显示的是当前成员已用量和可用上限，不代表组织总池"
            )
        ]
    }

    private static func enterpriseSnapshots(now: Date) -> [ProviderSnapshot] {
        let monthlyReset = now.addingTimeInterval(24 * 24 * 60 * 60)
        return [
            snapshot(
                .codex,
                plan: "Enterprise",
                category: .enterprise,
                now: now,
                metrics: [
                    UsageMetric(
                        id: "monthly_usage",
                        title: "本月我的用量",
                        usedPercent: 0,
                        deadlineAt: nil,
                        group: .onDemand,
                        value: .quantity(
                            used: 1_260,
                            limit: nil,
                            remaining: nil,
                            unit: "credits"
                        ),
                        showsProgress: false
                    )
                ],
                note: "由组织统一结算；没有固定上限时不显示剩余百分比"
            ),
            snapshot(
                .cursor,
                plan: "Enterprise",
                category: .enterprise,
                now: now,
                metrics: cursorIncludedMetrics(
                    total: 26,
                    auto: 17,
                    api: 48,
                    reset: monthlyReset,
                    duration: 30 * 24 * 60 * 60
                ) + [
                    UsageMetric(
                        id: "on_demand_personal",
                        title: "我的消费",
                        usedPercent: 19.1,
                        deadlineAt: monthlyReset,
                        windowDuration: 30 * 24 * 60 * 60,
                        group: .onDemand,
                        value: .usd(usedCents: 19_100, limitCents: 100_000)
                    ),
                    UsageMetric(
                        id: "on_demand_team",
                        title: "组织总消费",
                        usedPercent: 42.4,
                        deadlineAt: monthlyReset,
                        windowDuration: 30 * 24 * 60 * 60,
                        group: .onDemand,
                        value: .usd(usedCents: 4_240_000, limitCents: 10_000_000)
                    )
                ],
                note: "组织数据仅在当前登录态实际返回这些字段时展示"
            ),
            snapshot(
                .claude,
                plan: "Enterprise",
                category: .enterprise,
                now: now,
                metrics: [
                    UsageMetric(
                        id: "monthly_usage",
                        title: "本月我的用量",
                        usedPercent: 0,
                        deadlineAt: nil,
                        group: .onDemand,
                        value: .usd(usedCents: 3_820, limitCents: nil),
                        showsProgress: false
                    )
                ],
                note: "按量计费由组织结算；普通成员看不到组织总消费"
            ),
            snapshot(
                .kiro,
                plan: "组织管理 · Pro+",
                category: .enterprise,
                now: now,
                metrics: [
                    credits(
                        id: "credits",
                        title: "我的月度 Credits",
                        used: 740,
                        limit: 2_000,
                        reset: monthlyReset,
                        duration: 30 * 24 * 60 * 60,
                        group: .included
                    )
                ],
                note: "仅显示当前成员 Credits；不伪造组织总用量"
            ),
            snapshot(
                .qoder,
                plan: "Enterprise",
                category: .enterprise,
                now: now,
                metrics: [
                    credits(
                        id: "shared",
                        title: "组织共享 Credits",
                        used: 720,
                        limit: 5_000,
                        reset: nil,
                        duration: nil,
                        group: .organizationShared
                    )
                ],
                note: "企业席位使用组织共享 Credits"
            )
        ]
    }

    private static func cursorIncludedMetrics(
        total: Double,
        auto: Double,
        api: Double,
        reset: Date,
        duration: TimeInterval
    ) -> [UsageMetric] {
        [
            percentage(
                id: "total",
                title: "总用量",
                used: total,
                reset: reset,
                duration: duration,
                group: .included
            ),
            percentage(
                id: "auto",
                title: "Auto",
                used: auto,
                reset: reset,
                duration: duration,
                group: .included
            ),
            percentage(
                id: "api",
                title: "指定模型（API）",
                used: api,
                reset: reset,
                duration: duration,
                group: .included
            )
        ]
    }

    private static func snapshot(
        _ provider: ProviderKind,
        plan: String,
        category: SubscriptionCategory,
        now: Date,
        metrics: [UsageMetric],
        note: String? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            planName: plan,
            metrics: metrics,
            fetchedAt: now,
            note: note,
            subscriptionCategory: category
        )
    }

    private static func percentage(
        id: String,
        title: String,
        used: Double,
        reset: Date?,
        duration: TimeInterval?,
        group: UsageMetric.Group
    ) -> UsageMetric {
        UsageMetric(
            id: id,
            title: title,
            usedPercent: used,
            deadlineAt: reset,
            windowDuration: duration,
            group: group
        )
    }

    private static func credits(
        id: String,
        title: String,
        used: Double,
        limit: Double,
        reset: Date?,
        duration: TimeInterval?,
        group: UsageMetric.Group,
        deadlineKind: UsageMetric.DeadlineKind = .reset
    ) -> UsageMetric {
        UsageMetric(
            id: id,
            title: title,
            usedPercent: limit > 0 ? used / limit * 100 : 0,
            deadlineAt: reset,
            deadlineKind: deadlineKind,
            windowDuration: duration,
            group: group,
            value: .quantity(
                used: used,
                limit: limit,
                remaining: nil,
                unit: "credits"
            )
        )
    }

    private static func remainingCredits(
        id: String,
        title: String,
        remaining: Double,
        group: UsageMetric.Group
    ) -> UsageMetric {
        UsageMetric(
            id: id,
            title: title,
            usedPercent: 0,
            deadlineAt: nil,
            group: group,
            value: .quantity(
                used: nil,
                limit: nil,
                remaining: remaining,
                unit: "credits"
            ),
            showsProgress: false
        )
    }
}
