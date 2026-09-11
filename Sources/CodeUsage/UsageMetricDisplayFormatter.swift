import Foundation

enum UsageMetricDisplayFormatter {
    static func groupTitle(
        _ group: UsageMetric.Group,
        provider: ProviderKind,
        snapshot: ProviderSnapshot
    ) -> String {
        switch snapshot.subscriptionCategory {
        case .freeTrial:
            switch group {
            case .included:
                let plan = snapshot.planName?.lowercased() ?? ""
                return plan.contains("trial") ? L10n.text("试用额度") : L10n.text("免费额度")
            case .onDemand: return L10n.text("额外用量")
            case .credits: return L10n.text("额外 Credits")
            case .personalAddOn: return L10n.text("额外 Credits")
            case .organizationShared: return L10n.text("组织共享额度")
            }
        case .individual:
            switch group {
            case .included: return L10n.text("套餐额度")
            case .onDemand: return L10n.text("按量付费")
            case .credits: return L10n.text("个人加购额度")
            case .personalAddOn: return L10n.text("个人加购额度")
            case .organizationShared: return L10n.text("组织共享额度")
            }
        case .team:
            switch group {
            case .included: return L10n.text("我的套餐额度")
            case .onDemand: return L10n.text("按量付费")
            case .credits:
                return provider == .qoder
                    ? L10n.text("组织共享额度")
                    : L10n.text("工作区额外用量")
            case .personalAddOn: return L10n.text("个人加购额度")
            case .organizationShared: return L10n.text("组织共享额度")
            }
        case .enterprise:
            switch group {
            case .included: return L10n.text("我的套餐额度")
            case .onDemand: return L10n.text("按量计费")
            case .credits: return L10n.text("组织共享额度")
            case .personalAddOn: return L10n.text("个人加购额度")
            case .organizationShared: return L10n.text("组织共享额度")
            }
        case .unknown:
            return group.title
        }
    }

    static func valueText(
        _ metric: UsageMetric,
        provider: ProviderKind,
        snapshot: ProviderSnapshot
    ) -> String? {
        guard let value = metric.value else { return nil }
        switch value {
        case .usd(let usedCents, let limitCents):
            let used = currency(usedCents, minimumFractionDigits: 2)
            if let limitCents {
                let limit = currency(limitCents, minimumFractionDigits: 0)
                if provider == .cursor, metric.id == "on_demand_personal" {
                    let label = L10n.text(metric.allowsLimitEditing ? "预算" : "消费上限")
                    return L10n.format("usage.value_labeled_limit", used, label, limit)
                }
                if provider == .cursor, metric.id == "on_demand_team" {
                    let label = L10n.text(
                        snapshot.subscriptionCategory == .enterprise
                            ? "组织上限"
                            : "团队上限"
                    )
                    return L10n.format("usage.value_labeled_limit", used, label, limit)
                }
                return L10n.format("usage.value_used_limit", used, limit)
            }
            return L10n.format(
                provider == .cursor ? "usage.value_spent" : "usage.value_used",
                used
            )
        case .quantity(let used, let limit, let remaining, let unit):
            if let used, let limit {
                return L10n.format(
                    "usage.quantity_used_limit",
                    decimal(used),
                    decimal(limit),
                    unit
                )
            }
            if let remaining {
                return L10n.format("usage.quantity_remaining", decimal(remaining), unit)
            }
            if let used {
                return L10n.format("usage.quantity_used", decimal(used), unit)
            }
            return nil
        }
    }

    private static func currency(
        _ cents: Int64,
        minimumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = 2
        let amount = formatter.string(from: NSNumber(value: Double(cents) / 100))
            ?? String(format: "%.2f", Double(cents) / 100)
        return "$\(amount)"
    }

    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", value)
    }
}
