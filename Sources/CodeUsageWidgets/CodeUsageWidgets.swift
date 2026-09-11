import AppKit
import AppIntents
import CodeUsageDisplay
import SwiftUI
import WidgetKit

private struct UsageTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedUsageSnapshot
    let selectedMetricIDs: [String]
}

@available(macOS 14.0, *)
struct UsageMetricOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let sections: [IntentItemSection<String>] = SharedUsageSnapshotStore
            .read()
            .providers
            .compactMap { provider in
                let items: [IntentItem<String>] = provider.displayMetrics.map { metric in
                    IntentItem<String>(
                        metricIdentifier(providerID: provider.id, metricID: metric.id),
                        title: "\(provider.title) · \(metric.title)",
                        subtitle: metric.groupTitle.map { "\($0)" }
                    )
                }
                guard !items.isEmpty else { return nil }
                return IntentItemSection<String>("\(provider.title)", items: items)
            }
        return IntentItemCollection(sections: sections)
    }
}

@available(macOS 14.0, *)
struct UsageWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "选择用量指标" }
    static var description: IntentDescription {
        "小号可选择 1 个指标，中号最多 3 个；大号始终显示全部指标。"
    }

    @Parameter(
        title: "显示指标",
        description: "小号选 1 个，中号最多选 3 个。",
        optionsProvider: UsageMetricOptionsProvider()
    )
    var firstMetricID: String?

    @Parameter(
        title: "第二个指标",
        optionsProvider: UsageMetricOptionsProvider()
    )
    var secondMetricID: String?

    @Parameter(
        title: "第三个指标",
        optionsProvider: UsageMetricOptionsProvider()
    )
    var thirdMetricID: String?

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .systemLarge) {
            Summary("显示全部指标")
        } otherwise: {
            When(widgetFamily: .equalTo, .systemSmall) {
                Summary("显示 \(\.$firstMetricID)")
            } otherwise: {
                Summary(
                    "显示 \(\.$firstMetricID)、\(\.$secondMetricID)、\(\.$thirdMetricID)"
                )
            }
        }
    }

    init() {}
}

@available(macOS 14.0, *)
private struct ConfigurableUsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageTimelineEntry {
        UsageTimelineEntry(
            date: Date(),
            snapshot: .preview,
            selectedMetricIDs: []
        )
    }

    func snapshot(
        for configuration: UsageWidgetConfigurationIntent,
        in context: Context
    ) async -> UsageTimelineEntry {
        UsageTimelineEntry(
            date: Date(),
            snapshot: context.isPreview ? .preview : SharedUsageSnapshotStore.read(),
            selectedMetricIDs: configuration.selectedMetricIDs
        )
    }

    func timeline(
        for configuration: UsageWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<UsageTimelineEntry> {
        let entry = UsageTimelineEntry(
            date: Date(),
            snapshot: SharedUsageSnapshotStore.read(),
            selectedMetricIDs: configuration.selectedMetricIDs
        )
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: 5,
            to: Date()
        ) ?? Date().addingTimeInterval(300)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

@available(macOS 14.0, *)
private extension UsageWidgetConfigurationIntent {
    var selectedMetricIDs: [String] {
        var seen: Set<String> = []
        return [firstMetricID, secondMetricID, thirdMetricID]
            .compactMap { $0 }
            .filter { seen.insert($0).inserted }
    }
}

@available(macOS 14.0, *)
@main
struct CodeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ConfigurableUsageWidget()
    }
}

@available(macOS 14.0, *)
private struct ConfigurableUsageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "\(SharedUsageSnapshotStore.widgetKindPrefix).full",
            intent: UsageWidgetConfigurationIntent.self,
            provider: ConfigurableUsageTimelineProvider()
        ) { entry in
            UsageWidgetView(entry: entry)
                .widgetURL(URL(string: "codeusage://open"))
        }
        .configurationDisplayName("CodeUsage 用量")
        .description("小号和中号可自选指标，大号显示全部用量。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct SynchronizedMetricItem: Identifiable {
    let provider: SharedUsageProvider
    let metric: SharedUsageMetric

    var id: String { "\(provider.id).\(metric.id)" }
}

private extension SharedUsageSnapshot {
    var allMetricItems: [SynchronizedMetricItem] {
        providers.flatMap { provider in
            provider.displayMetrics.map {
                SynchronizedMetricItem(provider: provider, metric: $0)
            }
        }
    }

    var primaryMetricItems: [SynchronizedMetricItem] {
        providers.compactMap { provider in
            provider.primaryMetric.map {
                SynchronizedMetricItem(provider: provider, metric: $0)
            }
        }
    }

    var mostUsedPrimaryItem: SynchronizedMetricItem? {
        primaryMetricItems.max {
            ($0.metric.usedPercent ?? -1) < ($1.metric.usedPercent ?? -1)
        }
    }

    func selectedMetricItems(
        identifiers: [String],
        limit: Int
    ) -> [SynchronizedMetricItem] {
        guard !identifiers.isEmpty else {
            return Array(primaryMetricItems.prefix(limit))
        }
        let itemsByID = Dictionary(
            uniqueKeysWithValues: allMetricItems.map { ($0.id, $0) }
        )
        let selected = identifiers.compactMap { itemsByID[$0] }
        return selected.isEmpty
            ? Array(primaryMetricItems.prefix(limit))
            : Array(selected.prefix(limit))
    }
}

private func metricIdentifier(providerID: String, metricID: String) -> String {
    "\(providerID).\(metricID)"
}

private struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageTimelineEntry

    @ViewBuilder
    var body: some View {
        switch family {
        case .systemSmall:
            BriefWidgetView(entry: entry)
        case .systemLarge:
            FullWidgetView(entry: entry)
        default:
            ModerateWidgetView(entry: entry)
        }
    }
}

private struct BriefWidgetView: View {
    let entry: UsageTimelineEntry

    private var item: SynchronizedMetricItem? {
        if !entry.selectedMetricIDs.isEmpty {
            return entry.snapshot.selectedMetricItems(
                identifiers: entry.selectedMetricIDs,
                limit: 1
            ).first
        }
        return entry.snapshot.mostUsedPrimaryItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let item {
                HStack(spacing: 6) {
                    ProviderSymbol(providerID: item.provider.id)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.provider.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let planName = item.provider.planName, !planName.isEmpty {
                            Text(planName)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Text(item.metric.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let usedPercent = item.metric.usedPercent {
                    Text(WidgetLocalization.format(
                        "usage.used_percent",
                        Int(usedPercent.rounded())
                    ))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(progressColor(for: usedPercent))
                    ProgressView(value: usedPercent, total: 100)
                        .progressViewStyle(.linear)
                        .tint(progressColor(for: usedPercent))
                } else if let valueText = item.metric.valueText {
                    Text(valueText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                MetricFootnote(metric: item.metric, compact: true)
            } else {
                WidgetEmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .codeUsageWidgetBackground()
    }
}

private struct ModerateWidgetView: View {
    let entry: UsageTimelineEntry

    private var items: [SynchronizedMetricItem] {
        entry.snapshot.selectedMetricItems(
            identifiers: entry.selectedMetricIDs,
            limit: 3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MetricSummaryList(items: items)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .codeUsageWidgetBackground()
    }
}

private struct FullWidgetView: View {
    let entry: UsageTimelineEntry

    private var providers: [SharedUsageProvider] {
        entry.snapshot.providers.filter { !$0.displayMetrics.isEmpty }
    }

    private var density: FullWidgetDensity {
        providers.reduce(0) { $0 + $1.displayMetrics.count } >= 10
            ? .dense
            : .regular
    }

    private var providerColumns: [[SharedUsageProvider]] {
        let indexedProviders = providers.enumerated().map {
            IndexedUsageProvider(index: $0.offset, provider: $0.element)
        }
        let placementOrder = indexedProviders.sorted {
            if $0.provider.fullLayoutWeight == $1.provider.fullLayoutWeight {
                return $0.index < $1.index
            }
            return $0.provider.fullLayoutWeight > $1.provider.fullLayoutWeight
        }
        var columns: [[IndexedUsageProvider]] = [[], []]
        var columnWeights = [0, 0]
        for item in placementOrder {
            let columnIndex = columnWeights[0] <= columnWeights[1] ? 0 : 1
            columns[columnIndex].append(item)
            columnWeights[columnIndex] += item.provider.fullLayoutWeight
        }
        if columns[1].contains(where: { $0.index == 0 }) {
            columns.swapAt(0, 1)
        }
        return columns.map { column in
            column.sorted { $0.index < $1.index }.map(\.provider)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .dense ? 5 : 7) {
            if providerColumns[0].isEmpty {
                WidgetEmptyState()
            } else {
                HStack(alignment: .top, spacing: density == .dense ? 7 : 9) {
                    FullProviderColumn(
                        providers: providerColumns[0],
                        density: density
                    )
                    if !providerColumns[1].isEmpty {
                        Divider().opacity(0.35)
                        FullProviderColumn(
                            providers: providerColumns[1],
                            density: density
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .codeUsageWidgetBackground()
    }
}

private enum FullWidgetDensity {
    case regular
    case dense
}

private struct IndexedUsageProvider {
    let index: Int
    let provider: SharedUsageProvider
}

private struct MetricSummaryList: View {
    let items: [SynchronizedMetricItem]

    var body: some View {
        if items.isEmpty {
            WidgetEmptyState()
        } else {
            VStack(spacing: 5) {
                ForEach(items) { item in
                    MetricSummaryRow(item: item)
                    if item.id != items.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }
}

private struct MetricSummaryRow: View {
    let item: SynchronizedMetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                ProviderSymbol(providerID: item.provider.id)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(item.provider.title)
                            .font(.system(size: 10, weight: .semibold))
                        if let planName = item.provider.planName, !planName.isEmpty {
                            Text(planName)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if item.provider.isStale {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }
                    }
                    .lineLimit(1)
                    Text(metricLabel(item.metric))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let usedPercent = item.metric.usedPercent {
                    Text(WidgetLocalization.format(
                        "usage.used_percent",
                        Int(usedPercent.rounded())
                    ))
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(progressColor(for: usedPercent))
                } else if let valueText = item.metric.valueText {
                    Text(valueText)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            if let usedPercent = item.metric.usedPercent {
                ProgressView(value: usedPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(progressColor(for: usedPercent))
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)
            }
        }
    }
}

private struct FullProviderColumn: View {
    let providers: [SharedUsageProvider]
    let density: FullWidgetDensity

    var body: some View {
        VStack(alignment: .leading, spacing: density == .dense ? 5 : 7) {
            ForEach(providers) { provider in
                FullProviderSection(provider: provider, density: density)
                if provider.id != providers.last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct FullProviderSection: View {
    let provider: SharedUsageProvider
    let density: FullWidgetDensity

    var body: some View {
        VStack(alignment: .leading, spacing: density == .dense ? 4 : 6) {
            HStack(spacing: 6) {
                ProviderSymbol(
                    providerID: provider.id,
                    compact: density == .dense
                )
                HStack(spacing: 4) {
                    Text(provider.title)
                        .font(.system(
                            size: density == .dense ? 9 : 10,
                            weight: .semibold
                        ))
                    if let planName = provider.planName, !planName.isEmpty {
                        Text(planName)
                            .font(.system(
                                size: density == .dense ? 7 : 8,
                                weight: .medium
                            ))
                            .foregroundStyle(.secondary)
                    }
                    if provider.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                }
                .lineLimit(1)
            }
            ForEach(provider.fullMetricGroups) { group in
                FullMetricGroupSection(group: group, density: density)
            }
        }
    }
}

private struct FullMetricGroup: Identifiable {
    let id: String
    let title: String?
    var metrics: [SharedUsageMetric]

    var commonDeadlineText: String? {
        guard let deadline = metrics.first?.deadlineText,
              !deadline.isEmpty,
              metrics.allSatisfy({ $0.deadlineText == deadline }) else {
            return nil
        }
        return deadline
    }
}

private extension SharedUsageProvider {
    var fullLayoutWeight: Int {
        let metrics = displayMetrics
        return 2
            + metrics.count * 2
            + fullMetricGroups.count
            + metrics.filter { $0.valueText != nil }.count
            + metrics.filter { $0.deadlineText != nil }.count
    }

    var fullMetricGroups: [FullMetricGroup] {
        var groups: [FullMetricGroup] = []
        for metric in displayMetrics {
            let title = metric.groupTitle.flatMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let identifier = title ?? "__ungrouped"
            if let index = groups.firstIndex(where: { $0.id == identifier }) {
                groups[index].metrics.append(metric)
            } else {
                groups.append(FullMetricGroup(
                    id: identifier,
                    title: title,
                    metrics: [metric]
                ))
            }
        }
        return groups
    }
}

private struct FullMetricGroupSection: View {
    let group: FullMetricGroup
    let density: FullWidgetDensity

    var body: some View {
        VStack(alignment: .leading, spacing: density == .dense ? 2 : 4) {
            if group.title != nil || group.commonDeadlineText != nil {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let title = group.title {
                        Text(title)
                            .font(.system(
                                size: density == .dense ? 7 : 8,
                                weight: .semibold
                            ))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    if let deadline = group.commonDeadlineText {
                        Text(deadline)
                            .font(.system(
                                size: density == .dense ? 6.5 : 7,
                                weight: .medium
                            ))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            ForEach(group.metrics) { metric in
                FullMetricRow(
                    metric: metric,
                    showsDeadline: group.commonDeadlineText == nil,
                    density: density
                )
                if density == .regular, metric.id != group.metrics.last?.id {
                    Divider().opacity(0.18)
                }
            }
        }
        .padding(.horizontal, density == .dense ? 5 : 7)
        .padding(.vertical, density == .dense ? 3 : 5)
        .background(
            .primary.opacity(0.045),
            in: RoundedRectangle(
                cornerRadius: density == .dense ? 6 : 7,
                style: .continuous
            )
        )
    }
}

private struct FullMetricRow: View {
    let metric: SharedUsageMetric
    let showsDeadline: Bool
    let density: FullWidgetDensity

    var body: some View {
        VStack(alignment: .leading, spacing: density == .dense ? 1 : 2) {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(
                        size: density == .dense ? 7.5 : 8,
                        weight: metric.isPrimary ? .semibold : .medium
                    ))
                    .lineLimit(1)
                Spacer(minLength: 3)
                if let usedPercent = metric.usedPercent {
                    Text(WidgetLocalization.format(
                        "usage.used_percent",
                        Int(usedPercent.rounded())
                    ))
                        .font(.system(
                            size: density == .dense ? 7.5 : 8,
                            weight: .bold
                        ))
                        .monospacedDigit()
                        .foregroundStyle(progressColor(for: usedPercent))
                } else if let valueText = metric.valueText {
                    Text(valueText)
                        .font(.system(
                            size: density == .dense ? 7 : 8,
                            weight: .semibold
                        ))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
            }
            if let usedPercent = metric.usedPercent {
                ProgressView(value: usedPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(progressColor(for: usedPercent))
                    .scaleEffect(
                        x: 1,
                        y: density == .dense ? 0.46 : 0.58,
                        anchor: .center
                    )
            }
            if let valueText = metric.valueText, metric.usedPercent != nil {
                Text(valueText)
                    .font(.system(
                        size: density == .dense ? 6.5 : 7,
                        weight: .medium
                    ))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(density == .dense ? 0.6 : 0.72)
                    .allowsTightening(true)
            }
            if showsDeadline, let deadline = metric.deadlineText {
                Text(deadline)
                    .font(.system(
                        size: density == .dense ? 6.5 : 7,
                        weight: .medium
                    ))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

private func metricLabel(_ metric: SharedUsageMetric) -> String {
    if let groupTitle = metric.groupTitle,
       !groupTitle.isEmpty,
       groupTitle != metric.title {
        return "\(groupTitle) · \(metric.title)"
    }
    return metric.title
}

private struct MetricFootnote: View {
    let metric: SharedUsageMetric
    let compact: Bool

    var body: some View {
        if metric.deadlineText != nil || metric.valueText != nil {
            HStack(spacing: 4) {
                if let valueText = metric.valueText {
                    Text(valueText)
                        .lineLimit(1)
                }
                if metric.valueText != nil, metric.deadlineText != nil {
                    Text("·")
                }
                if let deadlineText = metric.deadlineText {
                    Text(deadlineText)
                        .lineLimit(1)
                }
            }
            .font(.system(size: compact ? 7 : 8, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

private struct WidgetEmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.title2)
            Text("打开 CodeUsage 刷新用量")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProviderSymbol: View {
    let providerID: String
    var compact = false

    var body: some View {
        BundledTemplateIcon(
            fileName: "provider-\(providerID).svg",
            fallbackSystemName: "gauge.with.dots.needle.67percent",
            size: compact ? 12 : 14
        )
            .frame(width: compact ? 18 : 20, height: compact ? 18 : 20)
            .background(
                .primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: compact ? 4 : 5)
            )
            .accessibilityHidden(true)
    }
}

private struct BundledTemplateIcon: View {
    let fileName: String
    let fallbackSystemName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSystemName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
    }

    private var image: NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(fileName),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}

private func progressColor(for usedPercent: Double) -> Color {
    if usedPercent >= 90 { return .red }
    if usedPercent >= 70 { return .orange }
    return .accentColor
}

private extension View {
    @ViewBuilder
    func codeUsageWidgetBackground() -> some View {
        if #available(macOS 14.0, *) {
            self.containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.14), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            self.background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private extension SharedUsageSnapshot {
    static let preview = SharedUsageSnapshot(
        providers: [
            SharedUsageProvider(
                id: "codex",
                title: "Codex",
                planName: "Plus",
                metricTitle: "5 小时额度",
                remainingPercent: 68,
                isStale: false,
                metrics: [
                    SharedUsageMetric(
                        id: "weekly",
                        title: "周额度",
                        groupTitle: "套餐额度",
                        usedPercent: 32,
                        remainingPercent: 68,
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
                        usedPercent: 14,
                        remainingPercent: 86,
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
                planName: "Pro",
                metricTitle: "套餐内用量",
                remainingPercent: 42,
                isStale: false,
                metrics: [
                    SharedUsageMetric(
                        id: "total",
                        title: "套餐内总用量",
                        groupTitle: "套餐额度",
                        usedPercent: 58,
                        remainingPercent: 42,
                        deadlineText: "12 天后重置",
                        valueText: nil,
                        suggestedUsedPercent: 61,
                        showsProgress: true,
                        isPrimary: true
                    ),
                    SharedUsageMetric(
                        id: "auto",
                        title: "Auto",
                        groupTitle: "套餐额度",
                        usedPercent: 24,
                        remainingPercent: 76,
                        deadlineText: "12 天后重置",
                        valueText: nil,
                        suggestedUsedPercent: 61,
                        showsProgress: true,
                        isPrimary: false
                    ),
                    SharedUsageMetric(
                        id: "api",
                        title: "API",
                        groupTitle: "套餐额度",
                        usedPercent: 72,
                        remainingPercent: 28,
                        deadlineText: "12 天后重置",
                        valueText: nil,
                        suggestedUsedPercent: 61,
                        showsProgress: true,
                        isPrimary: false
                    ),
                    SharedUsageMetric(
                        id: "on_demand_personal",
                        title: "我的消费",
                        groupTitle: "按量付费",
                        usedPercent: 5,
                        remainingPercent: 95,
                        deadlineText: "12 天后重置",
                        valueText: "已用 $23.40 / 预算 $500",
                        suggestedUsedPercent: 61,
                        showsProgress: true,
                        isPrimary: false
                    )
                ]
            ),
            SharedUsageProvider(
                id: "claude",
                title: "Claude Code",
                planName: "Max",
                metricTitle: "周额度",
                remainingPercent: 81,
                isStale: false,
                metrics: [
                    SharedUsageMetric(
                        id: "weekly",
                        title: "周额度",
                        groupTitle: "套餐额度",
                        usedPercent: 19,
                        remainingPercent: 81,
                        deadlineText: "5 天后重置",
                        valueText: nil,
                        suggestedUsedPercent: 29,
                        showsProgress: true,
                        isPrimary: true
                    ),
                    SharedUsageMetric(
                        id: "session",
                        title: "会话额度",
                        groupTitle: "套餐额度",
                        usedPercent: 45,
                        remainingPercent: 55,
                        deadlineText: "3 小时后重置",
                        valueText: nil,
                        suggestedUsedPercent: 60,
                        showsProgress: true,
                        isPrimary: false
                    )
                ]
            )
        ],
        updatedAt: Date(),
        isRefreshing: false
    )
}

private enum WidgetLocalization {
    static func text(_ key: String) -> String {
        let localized = Bundle.main.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
        if localized != key { return localized }
        guard let englishPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let englishBundle = Bundle(path: englishPath) else { return key }
        return englishBundle.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
