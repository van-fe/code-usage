#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CACHE_DIR="$PROJECT_DIR/.cache/self-test"
mkdir -p "$CACHE_DIR"

METRIC_HELP_KEYS=(
  "这是 Cursor 返回的 Auto 类别额度使用百分比，不等于你选择 Auto 的请求量或花费。Auto 可能路由到其他模型额度池；各项百分比不能相加。"
  "这是 Cursor 返回的 API 类别额度使用百分比，并非只统计手动选择的模型；Auto 路由到第三方模型时也可能计入。这里的“API”不是你自己的 API Key。"
  "这是第三方模型套餐额度的进度；Auto 路由到第三方模型时也可能计入这里。"
  "点击设置显示预算。CodeUsage 会据此显示消费进度；这个金额不会更改 Cursor 的消费上限。"
  "预算只用于显示按量付费进度和剩余额度，不会限制实际消费"
  "基础套餐额度"
  "其他模型（API）"
  "综合额度进度"
  "Claude 账号的共用订阅额度"
  "消费与共享额度"
  "menu.provider_remaining_metric"
  "menu.cursor.reported_progress"
  "menu.cursor.personal_spend_limit_remaining"
  "metric.help.cursor.total_base"
  "metric.help.cursor.total_reported"
  "metric.help.cursor.personal"
  "metric.help.cursor.personal_enterprise"
  "metric.help.cursor.organization"
  "metric.help.cursor.team"
  "metric.help.codex.window"
  "metric.help.codex.individual_limit"
  "metric.help.codex.workspace_credits"
  "metric.help.claude.window"
  "metric.help.qoder.included"
  "metric.help.qoder.add_on"
  "metric.help.qoder.shared"
  "metric.help.qoder.total"
  "metric.help.kiro.credits"
  "metric.help.kiro.add_on"
)

WIDGET_CONFIGURATION_KEYS=(
  "用量指标"
  "选择用量指标"
  "小号可选择 1 个指标，中号最多 3 个；大号始终显示全部指标。"
  "显示指标"
  "第二个指标"
  "第三个指标"
  "显示全部指标"
  "小号选 1 个，中号最多选 3 个。"
  "小号和中号可自选指标，大号显示全部用量。"
)

for LOCALIZATION in "$PROJECT_DIR/Sources/CodeUsage/Resources"/*.lproj/Localizable.strings; do
  /usr/bin/plutil -lint "$LOCALIZATION" >/dev/null
  for KEY in "${METRIC_HELP_KEYS[@]}"; do
    if ! /usr/bin/grep -Fq "\"$KEY\" =" "$LOCALIZATION"; then
      print -u2 "Missing metric help translation in $LOCALIZATION: $KEY"
      exit 1
    fi
  done
  for KEY in "${WIDGET_CONFIGURATION_KEYS[@]}"; do
    if ! /usr/bin/grep -Fq "\"$KEY\" =" "$LOCALIZATION"; then
      print -u2 "Missing widget configuration translation in $LOCALIZATION: $KEY"
      exit 1
    fi
  done
done

swiftc \
  -module-cache-path "$CACHE_DIR" \
  -parse-as-library \
  "$PROJECT_DIR/Sources/CodeUsageDisplay/SharedUsageSnapshot.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/Localization.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/Models.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/CloudSync.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/SubscriptionSimulation.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/ProcessUtils.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/CodexProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/CursorProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/ClaudeProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/KiroProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/QoderProvider.swift" \
  "$PROJECT_DIR/Scripts/SelfTest.swift" \
  -framework CloudKit \
  -framework Security \
  -o "$CACHE_DIR/CodeUsageSelfTest"

"$CACHE_DIR/CodeUsageSelfTest"
