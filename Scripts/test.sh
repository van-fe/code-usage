#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CACHE_DIR="$PROJECT_DIR/.cache/self-test"
mkdir -p "$CACHE_DIR"

swiftc \
  -module-cache-path "$CACHE_DIR" \
  -parse-as-library \
  "$PROJECT_DIR/Sources/CodeUsage/Models.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/SubscriptionSimulation.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/ProcessUtils.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/CodexProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/CursorProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/ClaudeProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/KiroProvider.swift" \
  "$PROJECT_DIR/Sources/CodeUsage/QoderProvider.swift" \
  "$PROJECT_DIR/Scripts/SelfTest.swift" \
  -o "$CACHE_DIR/CodeUsageSelfTest"

"$CACHE_DIR/CodeUsageSelfTest"
