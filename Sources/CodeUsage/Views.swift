import AppKit
import SwiftUI

private let suggestedUsageColor = Color(red: 0.22, green: 0.78, blue: 0.53)

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @State private var showsArchivedProviders = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isSimulationMode {
                simulationSwitcher
                Divider()
            }
            ScrollView(.vertical) {
                providerContent
            }
            .frame(maxHeight: 600)
            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var providerContent: some View {
        VStack(spacing: 12) {
            if store.installedProviders.isEmpty {
                emptyState
            } else if store.displayedProviders.isEmpty {
                allProvidersArchivedState
            } else {
                ForEach(store.displayedProviders) { provider in
                    ProviderCard(
                        provider: provider,
                        state: store.state(for: provider),
                        showsSubscriptionGroups: store.isSimulationMode,
                        isShownInMenuBar: store.isShownInMenuBar(provider),
                        cursorIndividualLimitDollars: store.cursorIndividualLimitDollars,
                        toggleMenuBarVisibility: {
                            store.toggleMenuBarVisibility(provider)
                        },
                        archiveProvider: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsArchivedProviders = true
                                store.archive(provider)
                            }
                        },
                        setCursorIndividualLimitDollars: { value in
                            store.setCursorIndividualLimitDollars(value)
                        }
                    )
                }
            }
            if !store.archivedProvidersList.isEmpty {
                archivedProvidersSection
            }
        }
        .padding(14)
    }

    private var allProvidersArchivedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.secondary)
            Text("所有已安装工具均已归档")
                .font(.headline)
            Text("可在下方的已归档列表中恢复显示。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var archivedProvidersSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsArchivedProviders.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsArchivedProviders ? 90 : 0))
                        .animation(
                            .easeInOut(duration: 0.18),
                            value: showsArchivedProviders
                        )
                    Label("已归档", systemImage: "archivebox")
                        .font(.caption.weight(.semibold))
                    Text("\(store.archivedProvidersList.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.primary.opacity(0.06), in: Capsule())
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showsArchivedProviders ? "收起已归档列表" : "展开已归档列表")
            .accessibilityLabel("已归档，\(store.archivedProvidersList.count) 个工具")
            .accessibilityValue(showsArchivedProviders ? "已展开" : "已收起")
            .accessibilityHint(showsArchivedProviders ? "点击收起列表" : "点击展开列表")

            if showsArchivedProviders {
                Divider()
                    .padding(.horizontal, 11)

                VStack(spacing: 0) {
                    ForEach(store.archivedProvidersList) { provider in
                        HStack(spacing: 8) {
                            ProviderAppIcon(provider: provider, size: 18)
                            Text(provider.title)
                                .font(.caption.weight(.medium))
                            if !store.installedProviders.contains(provider) {
                                Text("未检测到安装")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("取消归档") {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    store.unarchive(provider)
                                }
                            }
                            .buttonStyle(CompactActionButtonStyle())
                            .font(.caption2)
                            .accessibilityLabel("取消归档 \(provider.title)")
                        }
                        .padding(.vertical, 7)

                        if provider != store.archivedProvidersList.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 4)
            }
        }
        .background(.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)

            Text("未检测到支持的工具")
                .font(.headline)

            Text("请先安装 Codex、Cursor、Claude Code、Kiro 或 Qoder，\n安装完成后重新检测。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await store.refresh() }
            } label: {
                Label("重新检测", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CompactActionButtonStyle())
            .font(.caption)
            .disabled(store.isRefreshing)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            CodeUsageLogo(size: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("CodeUsage")
                    .font(.headline)

                Text(store.isSimulationMode
                    ? "订阅模拟 · 示例数据仅用于界面检查"
                    : "Codex、Cursor、Claude 等 AI 编程工具用量一览")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }

            Spacer(minLength: 4)

            ZStack {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(CompactIconButtonStyle())
                .help(store.isSimulationMode
                    ? "重置当前模拟数据"
                    : "刷新所有工具的用量")
                .accessibilityLabel(store.isSimulationMode
                    ? "重置当前模拟数据"
                    : "刷新所有工具的用量")
                .opacity(store.isRefreshing ? 0 : 1)
                .disabled(store.isRefreshing)

                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
                    .opacity(store.isRefreshing ? 1 : 0)
            }
            .frame(width: 28, height: 28, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var simulationSwitcher: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("按订阅类型预览", systemImage: "rectangle.3.group")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("模拟数据")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Picker(
                "订阅类型",
                selection: Binding(
                    get: { store.simulationCategory ?? .freeTrial },
                    set: { store.setSimulationCategory($0) }
                )
            ) {
                ForEach([
                    SubscriptionCategory.freeTrial,
                    .individual,
                    .team,
                    .enterprise
                ]) { category in
                    Text(category.title).tag(category)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.045))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if store.isSimulationMode {
                Text("模拟数据 · 不读取真实账号")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let updated = store.lastUpdated {
                Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("每 5 分钟自动刷新")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openGitHubRepository()
            } label: {
                GitHubMarkIcon(size: 12)
            }
            .buttonStyle(CompactIconButtonStyle())
            .accessibilityLabel("打开 CodeUsage 的 GitHub 页面")
            .accessibilityHint("使用默认浏览器打开")

            if !store.isSimulationMode {
                Toggle(
                    "iCloud",
                    isOn: Binding(
                        get: { store.isCloudSyncEnabled },
                        set: { store.setCloudSyncEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
                .help(cloudSyncHelp)

                Toggle(
                    "开机启动",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.caption)
                .help(launchAtLoginHelp)

                if launchAtLogin.requiresApproval {
                    Button {
                        launchAtLogin.openApprovalSettings()
                    } label: {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(CompactIconButtonStyle())
                    .arrowHoverHelp(
                        "点击打开“系统设置 → 通用 → 登录项”，然后允许 CodeUsage 开机启动。",
                        width: 270
                    )
                    .accessibilityLabel("打开登录项设置")
                    .accessibilityHint("允许 CodeUsage 在登录 Mac 时自动启动")
                } else if let error = launchAtLogin.errorMessage {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .arrowHoverHelp(error, width: 280)
                        .accessibilityLabel(error)
                }
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
                .buttonStyle(CompactActionButtonStyle())
            .font(.caption)
            .help("退出 CodeUsage")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var launchAtLoginHelp: String {
        if launchAtLogin.requiresApproval {
            return "开机启动还没生效。请到“系统设置 → 通用 → 登录项”允许 CodeUsage。"
        }
        if launchAtLogin.isEnabled {
            return "关闭后，CodeUsage 将不再随 Mac 登录自动启动。"
        }
        return "开启后，登录 Mac 时会自动启动 CodeUsage。"
    }

    private var cloudSyncHelp: String {
        switch store.cloudSyncStatus {
        case .disabled:
            return "开启后，只把用量展示快照同步到你的 iCloud 私有数据库。"
        case .idle:
            return "已开启；下次刷新后会同步用量快照。"
        case .syncing:
            return "正在同步用量快照到 iCloud…"
        case .synced(let date):
            return "最近同步于 \(date.formatted(date: .omitted, time: .shortened))。"
        case .unavailable(let message):
            return message
        }
    }

    private func openGitHubRepository() {
        guard let url = URL(string: "https://github.com/van-fe/code-usage") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct CodeUsageLogo: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = templateIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
            } else {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityLabel("CodeUsage")
    }

    private var templateIcon: NSImage? {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("statusbar-logo.svg"),
              let image = NSImage(contentsOf: resourceURL) else { return nil }
        image.isTemplate = true
        return image
    }
}

private struct GitHubMarkIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = templateIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
            } else {
                Image(systemName: "link")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }

    private var templateIcon: NSImage? {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("github-mark.svg"),
              let image = NSImage(contentsOf: resourceURL) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}

private struct PlanBadge: View {
    let text: String

    private let maximumTextWidth: CGFloat = 104

    var body: some View {
        Group {
            if needsTooltip {
                truncatedBadge.arrowHoverHelp("套餐：\(text)", width: tooltipWidth)
            } else {
                fullBadge
            }
        }
    }

    private var fullBadge: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .accessibilityLabel("套餐：\(text)")
    }

    private var truncatedBadge: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: maximumTextWidth, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .accessibilityLabel("套餐：\(text)")
    }

    private var textWidth: CGFloat {
        (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(
                ofSize: NSFont.smallSystemFontSize,
                weight: .semibold
            )
        ]).width
    }

    private var needsTooltip: Bool {
        textWidth > maximumTextWidth
    }

    private var tooltipWidth: CGFloat {
        min(max(ceil(textWidth) + 28, 140), 280)
    }
}

private struct ProviderCard: View {
    let provider: ProviderKind
    let state: ProviderDisplayState
    let showsSubscriptionGroups: Bool
    let isShownInMenuBar: Bool
    let cursorIndividualLimitDollars: Double?
    let toggleMenuBarVisibility: () -> Void
    let archiveProvider: () -> Void
    let setCursorIndividualLimitDollars: (Double?) -> Void
    @State private var isEditingCursorLimit = false
    @State private var cursorLimitDraft = ""
    @State private var copiedLoginCommand: String?
    @State private var expandedMetricSectionIDs: Set<String> = []
    @FocusState private var cursorLimitFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderAppIcon(provider: provider, size: 20)
                Text(provider.title).font(.headline)
                if let plan = state.snapshot?.planName, !plan.isEmpty {
                    PlanBadge(text: plan)
                }
                Spacer()
                Menu {
                    if hasOpenActions {
                        if let applicationTitle = ProviderAppLauncher.applicationTitle(for: provider) {
                            Button {
                                ProviderAppLauncher.openApplication(provider)
                            } label: {
                                Label(applicationTitle, systemImage: applicationIcon)
                            }
                        }
                        if ProviderInstallation.cliExecutable(for: provider) != nil {
                            Button {
                                ProviderAppLauncher.openCLI(provider)
                            } label: {
                                Label(cliActionTitle, systemImage: "terminal")
                            }
                        }
                        Divider()
                    }
                    Button(action: toggleMenuBarVisibility) {
                        Label(
                            isShownInMenuBar ? "从状态栏隐藏" : "在状态栏显示",
                            systemImage: isShownInMenuBar ? "eye.slash" : "eye"
                        )
                    }
                    Divider()
                    Button(action: archiveProvider) {
                        Label("归档", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(CompactIconButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多操作")
                .accessibilityLabel("\(provider.title) 更多操作")
                if state.isStale {
                    Text("旧数据")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let snapshot = state.snapshot {
                metricsContent(snapshot.metrics)
                if let note = snapshot.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = state.errorMessage {
                    errorContent(error, isStale: true)
                }
            } else if let error = state.errorMessage {
                errorContent(error, isStale: false)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func errorContent(_ error: String, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                error,
                systemImage: isStale
                    ? "exclamationmark.triangle.fill"
                    : "exclamationmark.circle"
            )
            .font(isStale ? .caption2 : .caption)
            .foregroundStyle(isStale ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if state.requiresSignIn {
                if let command = ProviderInstallation.loginCommand(for: provider) {
                    Text("请在终端运行以下命令，登录完成后刷新：")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(command)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 2)
                        Button {
                            copyLoginCommand(command)
                        } label: {
                            Label(
                                copiedLoginCommand == command ? "已复制" : "复制",
                                systemImage: copiedLoginCommand == command
                                    ? "checkmark"
                                    : "doc.on.doc"
                            )
                        }
                        .buttonStyle(CompactActionButtonStyle())
                        .font(.caption2)
                        .accessibilityLabel("复制 \(provider.title) 登录命令")
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 7)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("请从右上角菜单打开应用，完成登录后刷新。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copyLoginCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedLoginCommand = command
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedLoginCommand == command {
                copiedLoginCommand = nil
            }
        }
    }

    private var applicationIcon: String {
        switch provider {
        case .cursor, .kiro, .qoder:
            return "chevron.left.forwardslash.chevron.right"
        case .codex, .claude:
            return "macwindow"
        }
    }

    private var hasOpenActions: Bool {
        ProviderAppLauncher.applicationTitle(for: provider) != nil ||
            ProviderInstallation.cliExecutable(for: provider) != nil
    }

    private var cliActionTitle: String {
        switch provider {
        case .codex: return "在终端启动 Codex"
        case .cursor: return "在终端启动 Cursor CLI"
        case .claude: return "在终端启动 Claude Code"
        case .kiro: return "在终端启动 Kiro CLI"
        case .qoder: return "在终端启动 Qoder CLI"
        }
    }

    private struct MetricSection: Identifiable {
        let id: String
        let group: UsageMetric.Group?
        var metrics: [UsageMetric]
    }

    private func metricsContent(_ metrics: [UsageMetric]) -> some View {
        let groups = metrics.compactMap(\.group)
        let showsGroupHeaders = showsSubscriptionGroups ||
            groups.dropFirst().contains { $0 != groups.first }
        let sections = metricSections(metrics)
        return VStack(alignment: .leading, spacing: 9) {
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                let groupTimeline = sharedTimeline(for: section.metrics)
                if showsGroupHeaders,
                   let group = section.group {
                    metricGroupHeader(
                        group,
                        isFirst: index == 0,
                        timeline: groupTimeline
                    )
                }
                if let summaryMetric = section.metrics.first {
                    metricRow(
                        summaryMetric,
                        showsInlineTimeline: !showsGroupHeaders || groupTimeline == nil
                    )
                }
                if section.metrics.count > 1 {
                    metricDetails(
                        section,
                        showsInlineTimeline: !showsGroupHeaders || groupTimeline == nil
                    )
                }
            }
        }
    }

    private func metricSections(_ metrics: [UsageMetric]) -> [MetricSection] {
        var sections: [MetricSection] = []
        for metric in metrics {
            if let lastIndex = sections.indices.last,
               sections[lastIndex].group == metric.group {
                sections[lastIndex].metrics.append(metric)
            } else {
                let groupID = metric.group?.rawValue ?? "ungrouped"
                sections.append(MetricSection(
                    id: "\(groupID)-\(sections.count)",
                    group: metric.group,
                    metrics: [metric]
                ))
            }
        }
        return sections
    }

    @ViewBuilder
    private func metricDetails(
        _ section: MetricSection,
        showsInlineTimeline: Bool
    ) -> some View {
        let isExpanded = expandedMetricSectionIDs.contains(section.id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedMetricSectionIDs.remove(section.id)
                    } else {
                        expandedMetricSectionIDs.insert(section.id)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(isExpanded
                        ? "收起明细"
                        : "另外 \(section.metrics.count - 1) 项明细")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起用量明细" : "展开全部用量明细")
            .accessibilityLabel(
                isExpanded
                    ? "收起 \(provider.title) 用量明细"
                    : "展开 \(provider.title) 的另外 \(section.metrics.count - 1) 项用量明细"
            )
            .accessibilityValue(isExpanded ? "已展开" : "已收起")

            if isExpanded {
                ForEach(Array(section.metrics.dropFirst())) { metric in
                    metricRow(metric, showsInlineTimeline: showsInlineTimeline)
                }
            }
        }
        .padding(.leading, 8)
    }

    private struct SharedMetricTimeline: Equatable {
        let deadline: String
        let suggestedPercent: Int?
    }

    private func sharedTimeline(for metrics: [UsageMetric]) -> SharedMetricTimeline? {
        let progressMetrics = metrics.filter(\.showsProgress)
        guard !progressMetrics.isEmpty else { return nil }

        let deadlines = progressMetrics.compactMap { $0.deadlineDescription() }
        guard deadlines.count == progressMetrics.count,
              let deadline = deadlines.first,
              deadlines.dropFirst().allSatisfy({ $0 == deadline })
        else { return nil }

        let suggestions = progressMetrics.compactMap {
            $0.suggestedUsedPercent().map { Int($0.rounded()) }
        }
        let suggestedPercent: Int?
        if suggestions.count == progressMetrics.count,
           let suggested = suggestions.first,
           suggestions.dropFirst().allSatisfy({ $0 == suggested }) {
            suggestedPercent = suggested
        } else {
            suggestedPercent = nil
        }

        return SharedMetricTimeline(
            deadline: deadline,
            suggestedPercent: suggestedPercent
        )
    }

    private func metricGroupHeader(
        _ group: UsageMetric.Group,
        isFirst: Bool,
        timeline: SharedMetricTimeline?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isFirst {
                Divider()
            }
            HStack(spacing: 6) {
                Text(metricGroupTitle(group))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let timeline {
                    HStack(spacing: 3) {
                        Text(timeline.deadline)
                            .foregroundStyle(.secondary)
                        if let suggested = timeline.suggestedPercent {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("建议 \(suggested)%")
                                .foregroundStyle(suggestedUsageColor)
                        }
                    }
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                }
            }
        }
    }

    private func metricGroupTitle(_ group: UsageMetric.Group) -> String {
        guard let snapshot = state.snapshot else { return group.title }
        switch snapshot.subscriptionCategory {
        case .freeTrial:
            switch group {
            case .included:
                let plan = snapshot.planName?.lowercased() ?? ""
                return plan.contains("trial") ? "试用额度" : "免费额度"
            case .onDemand: return "额外用量"
            case .credits: return "额外 Credits"
            case .personalAddOn: return "额外 Credits"
            case .organizationShared: return "组织共享额度"
            }
        case .individual:
            switch group {
            case .included: return "套餐额度"
            case .onDemand: return "按量付费"
            case .credits: return "个人加购额度"
            case .personalAddOn: return "个人加购额度"
            case .organizationShared: return "组织共享额度"
            }
        case .team:
            switch group {
            case .included: return "我的套餐额度"
            case .onDemand: return "按量付费"
            case .credits:
                return provider == .qoder ? "组织共享额度" : "工作区额外用量"
            case .personalAddOn: return "个人加购额度"
            case .organizationShared: return "组织共享额度"
            }
        case .enterprise:
            switch group {
            case .included: return "我的套餐额度"
            case .onDemand: return "按量计费"
            case .credits: return "组织共享额度"
            case .personalAddOn: return "个人加购额度"
            case .organizationShared: return "组织共享额度"
            }
        case .unknown:
            return group.title
        }
    }

    private func metricRow(
        _ metric: UsageMetric,
        showsInlineTimeline: Bool
    ) -> some View {
        let suggested = metric.showsProgress ? metric.suggestedUsedPercent() : nil
        let isCursorSummary = provider == .cursor && metric.id == "total"
        let isCursorDetail = provider == .cursor && ["auto", "api"].contains(metric.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Text(metric.title)
                    if let help = cursorMetricHelp(metric) {
                        MetricHelpIcon(
                            text: help,
                            accessibilityLabel: "关于“\(metric.title)”：\(help)"
                        )
                    }
                    if metric.allowsLimitEditing && !isEditingCursorLimit {
                        Button(action: beginEditingCursorLimit) {
                            Image(systemName: "arrow.up.to.line")
                                .font(.system(size: 9, weight: .regular))
                                .frame(width: 12, height: 12)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(CompactIconButtonStyle())
                        .arrowHoverHelp(cursorLimitEditHelp, width: 280)
                        .accessibilityLabel(cursorLimitAccessibilityLabel)
                        .accessibilityHint(
                            "预算只用于显示按量付费进度和剩余额度，不会限制实际消费"
                        )
                    }
                }
                .font(isCursorSummary ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(isCursorSummary ? Color.primary : Color.secondary)
                Spacer()
                if metric.id == "on_demand_personal", isEditingCursorLimit {
                    cursorLimitEditor
                } else if metric.showsProgress {
                    Text("已用 \(Int(metric.clampedPercent.rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if showsInlineTimeline,
                       let deadline = metric.deadlineDescription() {
                        Text("· \(deadline)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let valueText = metricValueText(metric) {
                    Text(valueText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            if metric.showsProgress {
                HStack(spacing: 7) {
                    UsageProgressBar(
                        usedPercent: metric.clampedPercent,
                        suggestedPercent: suggested,
                        fillColor: progressColor(metric.clampedPercent)
                    )
                    if showsInlineTimeline, let suggested {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(suggestedUsageColor)
                                .frame(width: 4, height: 4)
                            Text("建议 \(Int(suggested.rounded()))%")
                        }
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(suggestedUsageColor)
                        .fixedSize()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(progressAccessibilityLabel(metric, suggested: suggested))
                if let valueText = metricValueText(metric) {
                    Text(valueText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.leading, isCursorDetail ? 8 : 0)
    }

    private func progressAccessibilityLabel(_ metric: UsageMetric, suggested: Double?) -> String {
        var value = "已使用 \(Int(metric.clampedPercent.rounded()))%"
        if let suggested {
            value += "；按当前时间，建议最多用到 \(Int(suggested.rounded()))%"
        }
        return value
    }

    private func cursorMetricHelp(_ metric: UsageMetric) -> String? {
        guard provider == .cursor else { return nil }
        switch metric.id {
        case "total":
            return "这是本计费周期套餐内的整体用量。按量付费会在下方单独显示。"
        case "auto":
            return "这是使用 Auto（自动选择模型）时产生的套餐内用量。它不是一份独立额度，不要和总用量相加。"
        case "api":
            return "这是手动选择 Claude、GPT、Gemini 等模型时产生的套餐内用量。这里的“API”是 Cursor 的分类名，不是你自己的 API Key 消费。"
        case "on_demand_personal":
            if cursorSubscriptionCategory.hasSharedOrganizationContext {
                let sharedName = cursorSubscriptionCategory == .enterprise
                    ? "组织总消费"
                    : "团队总消费"
                return "这是你本期个人产生的按量付费金额，与“\(sharedName)”分开显示。显示预算只用于计算进度，不会限制实际消费。"
            }
            return "这是本计费周期超出套餐后产生的按量付费金额。显示预算只用于计算进度，不会限制实际消费。"
        case "on_demand_team":
            if cursorSubscriptionCategory == .enterprise {
                return "这是整个组织本期的按量付费总额和上限，不是你的个人额度。"
            }
            return "这是整个团队本期的按量付费总额和上限，不是你的个人额度。"
        default:
            return nil
        }
    }

    private var cursorLimitEditHelp: String {
        if let limit = cursorIndividualLimitDollars {
            return "当前按 $\(formattedLimit(limit)) 的显示预算计算进度。点击修改。这个金额不会更改 Cursor 的消费上限。"
        }
        return "点击设置显示预算。CodeUsage 会据此显示消费进度；这个金额不会更改 Cursor 的消费上限。"
    }

    private var cursorLimitAccessibilityLabel: String {
        if let limit = cursorIndividualLimitDollars {
            return "修改显示预算，当前为 $\(formattedLimit(limit))"
        }
        return "设置显示预算"
    }

    private var cursorSubscriptionCategory: SubscriptionCategory {
        state.snapshot?.subscriptionCategory ?? .unknown
    }

    private var cursorLimitEditor: some View {
        HStack(spacing: 3) {
            Text("$")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("例如 500", text: $cursorLimitDraft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                .focused($cursorLimitFieldFocused)
                .onSubmit(saveCursorLimit)
                .onExitCommand(perform: cancelEditingCursorLimit)
                .accessibilityLabel("显示预算金额（美元）")
                .accessibilityHint("输入大于 0 的金额；留空会清除显示预算")
            Button(action: saveCursorLimit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(CompactIconButtonStyle())
            .arrowHoverHelp("保存显示预算", width: 140)
            .accessibilityLabel("保存显示预算")
            Button(action: cancelEditingCursorLimit) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .regular))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(CompactIconButtonStyle())
            .arrowHoverHelp("取消修改", width: 120)
            .accessibilityLabel("取消修改显示预算")
        }
    }

    private func beginEditingCursorLimit() {
        cursorLimitDraft = cursorIndividualLimitDollars.map(formattedLimit) ?? ""
        isEditingCursorLimit = true
        DispatchQueue.main.async {
            cursorLimitFieldFocused = true
        }
    }

    private func saveCursorLimit() {
        let cleaned = cursorLimitDraft
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            setCursorIndividualLimitDollars(nil)
            cancelEditingCursorLimit()
            return
        }
        guard let value = Double(cleaned), value.isFinite, value > 0 else {
            NSSound.beep()
            cursorLimitFieldFocused = true
            return
        }
        setCursorIndividualLimitDollars(value)
        cancelEditingCursorLimit()
    }

    private func cancelEditingCursorLimit() {
        cursorLimitFieldFocused = false
        isEditingCursorLimit = false
    }

    private func formattedLimit(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func metricValueText(_ metric: UsageMetric) -> String? {
        guard let value = metric.value else { return nil }
        switch value {
        case .usd(let usedCents, let limitCents):
            let used = currency(usedCents, minimumFractionDigits: 2)
            if let limitCents {
                let limit = currency(limitCents, minimumFractionDigits: 0)
                if provider == .cursor, metric.id == "on_demand_personal" {
                    let label = metric.allowsLimitEditing ? "预算" : "消费上限"
                    return "\(used) / \(label) \(limit)"
                }
                if provider == .cursor, metric.id == "on_demand_team" {
                    let label = cursorSubscriptionCategory == .enterprise
                        ? "组织上限"
                        : "团队上限"
                    return "\(used) / \(label) \(limit)"
                }
                return "已用 \(used) / \(limit)"
            }
            return provider == .cursor ? "已消费 \(used)" : "已用 \(used)"
        case .quantity(let used, let limit, let remaining, let unit):
            if let used, let limit {
                return "已用 \(decimal(used)) / \(decimal(limit)) \(unit)"
            }
            if let remaining {
                return "剩余 \(decimal(remaining)) \(unit)"
            }
            if let used {
                return "已用 \(decimal(used)) \(unit)"
            }
            return nil
        }
    }

    private func currency(_ cents: Int64, minimumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = 2
        let amount = formatter.string(from: NSNumber(value: Double(cents) / 100))
            ?? String(format: "%.2f", Double(cents) / 100)
        return "$\(amount)"
    }

    private func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f", value)
    }

    private func progressColor(_ used: Double) -> Color {
        if used >= 90 { return .red }
        if used >= 70 { return .orange }
        return .accentColor
    }

}

private struct UsageProgressBar: View {
    let usedPercent: Double
    let suggestedPercent: Double?
    let fillColor: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(height: 6)
                Capsule()
                    .fill(fillColor)
                    .frame(width: width * usedPercent / 100, height: 6)
                if let suggestedPercent {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(suggestedUsageColor)
                        .frame(width: 2, height: 10)
                        .offset(x: markerOffset(width: width, percent: suggestedPercent))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    private func markerOffset(width: CGFloat, percent: Double) -> CGFloat {
        let center = width * min(max(percent, 0), 100) / 100
        return min(max(center - 1, 0), max(width - 2, 0))
    }
}

struct CompactActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CompactActionButtonBody(configuration: configuration)
    }
}

struct CompactIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CompactIconButtonBody(configuration: configuration)
    }
}

private struct CompactIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(4)
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.7)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed { return Color.primary.opacity(0.16) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    private var borderColor: Color {
        isHovering || configuration.isPressed
            ? Color.primary.opacity(0.1)
            : .clear
    }
}

private struct MetricHelpIcon: View {
    let text: String
    let accessibilityLabel: String

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 10.5, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .arrowHoverHelp(text, width: 280)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct ArrowHoverHelpModifier: ViewModifier {
    let text: String
    let width: CGFloat
    @State private var isHovering = false
    @State private var isPresented = false
    @State private var hoverGeneration = 0

    func body(content: Content) -> some View {
        content
            .background {
                TooltipAnchorView(
                    isPresented: isPresented,
                    text: text,
                    width: width
                )
                .allowsHitTesting(false)
            }
            .onHover { hovering in
                isHovering = hovering
                hoverGeneration += 1
                let generation = hoverGeneration

                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        guard isHovering, generation == hoverGeneration else { return }
                        isPresented = true
                    }
                } else {
                    isPresented = false
                }
            }
            .onChange(of: text) { _ in
                isPresented = false
            }
    }
}

private enum TooltipPlacement {
    case above
    case below
}

private struct ArrowTooltipBubble: View {
    let text: String
    let width: CGFloat
    let placement: TooltipPlacement
    let arrowCenterX: CGFloat

    private let arrowWidth: CGFloat = 14
    private let arrowHeight: CGFloat = 7

    var body: some View {
        VStack(spacing: 0) {
            if placement == .below {
                TooltipArrowShape(pointsUp: true)
                    .fill(backgroundColor)
                    .frame(width: arrowWidth, height: arrowHeight)
                    .frame(width: width, alignment: .leading)
                    .offset(x: arrowLeadingOffset)
            }

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(10)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(backgroundColor, in: RoundedRectangle(
                    cornerRadius: 8,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.18), lineWidth: 0.7)
                }

            if placement == .above {
                TooltipArrowShape(pointsUp: false)
                    .fill(backgroundColor)
                    .frame(width: arrowWidth, height: arrowHeight)
                    .frame(width: width, alignment: .leading)
                    .offset(x: arrowLeadingOffset)
            }
        }
        .frame(width: width)
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .accessibilityHidden(true)
    }

    private var backgroundColor: Color {
        Color(nsColor: .windowBackgroundColor).opacity(0.98)
    }

    private var arrowLeadingOffset: CGFloat {
        min(max(arrowCenterX - arrowWidth / 2, 10), width - arrowWidth - 10)
    }
}

private struct TooltipArrowShape: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private struct TooltipAnchorView: NSViewRepresentable {
    let isPresented: Bool
    let text: String
    let width: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            anchor: nsView,
            isPresented: isPresented,
            text: text,
            width: width
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hide()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?
        private var hostingView: NSHostingView<ArrowTooltipBubble>?
        private weak var parentWindow: NSWindow?
        private var observationTokens: [NSObjectProtocol] = []

        func update(anchor: NSView, isPresented: Bool, text: String, width: CGFloat) {
            guard isPresented,
                  let window = anchor.window,
                  window.isVisible else {
                hide()
                return
            }

            let windowRect = anchor.convert(anchor.bounds, to: nil)
            let anchorRect = window.convertToScreen(windowRect)
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })
                ?? window.screen
                ?? NSScreen.main
            guard let screen else {
                hide()
                return
            }

            let visibleFrame = screen.visibleFrame
            let gap: CGFloat = 5
            let initialBubble = ArrowTooltipBubble(
                text: text,
                width: width,
                placement: .above,
                arrowCenterX: width / 2
            )
            let hostingView = hostingView ?? NSHostingView(rootView: initialBubble)
            self.hostingView = hostingView
            hostingView.appearance = window.effectiveAppearance
            hostingView.rootView = initialBubble
            hostingView.layoutSubtreeIfNeeded()
            var contentSize = hostingView.fittingSize

            let aboveY = anchorRect.maxY + gap
            let belowY = anchorRect.minY - contentSize.height - gap
            let fitsAbove = aboveY + contentSize.height <= visibleFrame.maxY - 4
            let fitsBelow = belowY >= visibleFrame.minY + 4
            let placement: TooltipPlacement = fitsAbove || !fitsBelow ? .above : .below

            if placement == .below {
                hostingView.rootView = ArrowTooltipBubble(
                    text: text,
                    width: width,
                    placement: .below,
                    arrowCenterX: width / 2
                )
                hostingView.layoutSubtreeIfNeeded()
                contentSize = hostingView.fittingSize
            }

            let minimumX = visibleFrame.minX + 6
            let maximumX = max(minimumX, visibleFrame.maxX - contentSize.width - 6)
            let centeredX = anchorRect.midX - contentSize.width / 2
            let originX = min(max(centeredX, minimumX), maximumX)
            let preferredY = placement == .above
                ? anchorRect.maxY + gap
                : anchorRect.minY - contentSize.height - gap
            let minimumY = visibleFrame.minY + 4
            let maximumY = max(minimumY, visibleFrame.maxY - contentSize.height - 4)
            let originY = min(max(preferredY, minimumY), maximumY)
            let arrowCenterX = min(
                max(anchorRect.midX - originX, 17),
                contentSize.width - 17
            )

            hostingView.rootView = ArrowTooltipBubble(
                text: text,
                width: width,
                placement: placement,
                arrowCenterX: arrowCenterX
            )
            hostingView.layoutSubtreeIfNeeded()
            contentSize = hostingView.fittingSize

            let panel = panel ?? makePanel()
            self.panel = panel
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            if panel.contentView !== hostingView {
                panel.contentView = hostingView
            }
            panel.setFrame(
                NSRect(
                    origin: CGPoint(x: originX, y: originY),
                    size: contentSize
                ),
                display: true
            )
            attach(panel: panel, to: window, anchor: anchor)
            panel.orderFront(nil)
        }

        func hide() {
            stopObserving()
            if let panel, let parentWindow {
                parentWindow.removeChildWindow(panel)
            }
            parentWindow = nil
            panel?.orderOut(nil)
        }

        private func attach(panel: NSPanel, to window: NSWindow, anchor: NSView) {
            guard parentWindow !== window else { return }

            if let parentWindow {
                parentWindow.removeChildWindow(panel)
            }
            stopObserving()
            parentWindow = window
            window.addChildWindow(panel, ordered: .above)
            observeParentWindow(window)

            if let clipView = anchor.enclosingScrollView?.contentView {
                clipView.postsBoundsChangedNotifications = true
                observe(
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
        }

        private func observeParentWindow(_ window: NSWindow) {
            for name in [
                NSWindow.didResignKeyNotification,
                NSWindow.willCloseNotification,
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification
            ] {
                observe(name: name, object: window)
            }
            observe(name: .codeUsagePanelWillHide, object: window)
        }

        private func observe(name: Notification.Name, object: AnyObject) {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hide()
                }
            }
            observationTokens.append(token)
        }

        private func stopObserving() {
            for token in observationTokens {
                NotificationCenter.default.removeObserver(token)
            }
            observationTokens.removeAll()
        }

        private func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return panel
        }
    }
}

private extension View {
    func arrowHoverHelp(_ text: String, width: CGFloat) -> some View {
        modifier(ArrowHoverHelpModifier(text: text, width: width))
    }
}

private struct CompactActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed { return Color.primary.opacity(0.16) }
        if isHovering { return Color.primary.opacity(0.09) }
        return .clear
    }

    private var borderColor: Color {
        isHovering || configuration.isPressed
            ? Color.primary.opacity(0.12)
            : .clear
    }
}

struct ProviderAppIcon: View {
    let provider: ProviderKind
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = templateIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(ProviderIconMetrics.visualScale(for: provider))
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }

    private var templateIcon: NSImage? {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("provider-\(provider.rawValue).svg"),
              let image = NSImage(contentsOf: resourceURL) else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }

    private var fallbackSymbol: String {
        switch provider {
        case .codex: return "sparkles"
        case .cursor: return "cube"
        case .claude: return "asterisk"
        case .kiro: return "wand.and.stars"
        case .qoder: return "q.square"
        }
    }
}

enum ProviderAppLauncher {
    private struct ApplicationCandidate {
        let title: String
        let bundleIdentifiers: [String]
        let paths: [String]
    }

    static func applicationTitle(for provider: ProviderKind) -> String? {
        resolvedApplication(for: provider)?.candidate.title
    }

    static func openApplication(_ provider: ProviderKind) {
        guard let target = resolvedApplication(for: provider) else { return }
        NSWorkspace.shared.openApplication(
            at: target.url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openCLI(_ provider: ProviderKind) {
        guard let executable = ProviderInstallation.cliExecutable(for: provider) else { return }
        let commandURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeusage-\(provider.rawValue)-\(UUID().uuidString)")
            .appendingPathExtension("command")
        let script = """
        #!/bin/zsh
        command_file="$0"
        rm -f "$command_file"
        cd \(shellQuoted(FileManager.default.homeDirectoryForCurrentUser.path)) || exit 1
        exec \(shellQuoted(executable))
        """

        do {
            try script.write(to: commandURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: commandURL.path
            )
            if !NSWorkspace.shared.open(commandURL) {
                try? FileManager.default.removeItem(at: commandURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: commandURL)
        }
    }

    private static func candidates(for provider: ProviderKind) -> [ApplicationCandidate] {
        switch provider {
        case .codex:
            return [
                ApplicationCandidate(
                    title: "打开 Codex 桌面端",
                    bundleIdentifiers: [],
                    paths: [
                        "/Applications/Codex.app",
                        ProcessUtils.expandedHome("~/Applications/Codex.app")
                    ]
                ),
                ApplicationCandidate(
                    title: "打开 ChatGPT 桌面端",
                    bundleIdentifiers: ["com.openai.codex"],
                    paths: [
                        "/Applications/ChatGPT.app",
                        ProcessUtils.expandedHome("~/Applications/ChatGPT.app")
                    ]
                )
            ]
        case .cursor:
            return [ApplicationCandidate(
                title: "打开 Cursor IDE",
                bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
                paths: [
                    "/Applications/Cursor.app",
                    ProcessUtils.expandedHome("~/Applications/Cursor.app")
                ]
            )]
        case .claude:
            return [ApplicationCandidate(
                title: "打开 Claude 桌面端",
                bundleIdentifiers: ["com.anthropic.claudefordesktop"],
                paths: [
                    "/Applications/Claude.app",
                    ProcessUtils.expandedHome("~/Applications/Claude.app")
                ]
            )]
        case .kiro:
            return [ApplicationCandidate(
                title: "打开 Kiro IDE",
                bundleIdentifiers: ["dev.kiro.desktop"],
                paths: [
                    "/Applications/Kiro.app",
                    ProcessUtils.expandedHome("~/Applications/Kiro.app")
                ]
            )]
        case .qoder:
            return [ApplicationCandidate(
                title: "打开 Qoder IDE",
                bundleIdentifiers: ["com.qoder.ide"],
                paths: [
                    "/Applications/Qoder IDE.app",
                    "/Applications/Qoder.app",
                    ProcessUtils.expandedHome("~/Applications/Qoder IDE.app"),
                    ProcessUtils.expandedHome("~/Applications/Qoder.app")
                ]
            )]
        }
    }

    private static func resolvedApplication(
        for provider: ProviderKind
    ) -> (candidate: ApplicationCandidate, url: URL)? {
        for candidate in candidates(for: provider) {
            if let path = candidate.paths.first(where: {
                FileManager.default.fileExists(atPath: $0)
            }) {
                return (candidate, URL(fileURLWithPath: path))
            }
            if let url = candidate.bundleIdentifiers.lazy.compactMap({
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }).first {
                return (candidate, url)
            }
        }
        return nil
    }

    private static func shellQuoted(_ value: String) -> String {
        guard !value.allSatisfy({ $0.isLetter || $0.isNumber || "/._-".contains($0) })
        else { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
