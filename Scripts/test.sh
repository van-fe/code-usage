#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CACHE_DIR="$PROJECT_DIR/.cache/self-test"
mkdir -p "$CACHE_DIR"

CURSOR_HELP_KEYS=(
  "这是本计费周期套餐内的整体用量。按量付费会在下方单独显示。"
  "这是使用 Auto（自动选择模型）时产生的套餐内用量。它不是一份独立额度，不要和总用量相加。"
  "这是手动选择 Claude、GPT、Gemini 等模型时产生的套餐内用量。这里的“API”是 Cursor 的分类名，不是你自己的 API Key 消费。"
  "这是本计费周期超出套餐后产生的按量付费金额。显示预算只用于计算进度，不会限制实际消费。"
  "这是整个组织本期的按量付费总额和上限，不是你的个人额度。"
  "这是整个团队本期的按量付费总额和上限，不是你的个人额度。"
  "点击设置显示预算。CodeUsage 会据此显示消费进度；这个金额不会更改 Cursor 的消费上限。"
  "预算只用于显示按量付费进度和剩余额度，不会限制实际消费"
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
  for KEY in "${CURSOR_HELP_KEYS[@]}"; do
    if ! /usr/bin/grep -Fq "\"$KEY\" =" "$LOCALIZATION"; then
      print -u2 "Missing Cursor help translation in $LOCALIZATION: $KEY"
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
