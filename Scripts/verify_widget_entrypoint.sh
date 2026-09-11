#!/bin/zsh
set -euo pipefail

WIDGET_BINARY="${1:-}"
if [[ -z "$WIDGET_BINARY" || ! -f "$WIDGET_BINARY" ]]; then
  echo "Usage: $0 /path/to/CodeUsageWidgets" >&2
  exit 2
fi

WIDGET_ARCH_LIST=("${(@s: :)$(/usr/bin/lipo -archs "$WIDGET_BINARY")}")
for WIDGET_ARCH in "${WIDGET_ARCH_LIST[@]}"; do
  ENTRY_OFFSET=$(/usr/bin/otool -arch "$WIDGET_ARCH" -l "$WIDGET_BINARY" | \
    /usr/bin/awk '/cmd LC_MAIN/ { getline; getline; print $2; exit }')
  TEXT_VM_ADDRESS=$(/usr/bin/otool -arch "$WIDGET_ARCH" -l "$WIDGET_BINARY" | \
    /usr/bin/awk '/segname __TEXT/ { getline; print $2; exit }')
  EXTENSION_MAIN_STUB=$(/usr/bin/otool -arch "$WIDGET_ARCH" -Iv "$WIDGET_BINARY" | \
    /usr/bin/awk '$NF == "_NSExtensionMain" { print $1; exit }')

  if [[ -z "$ENTRY_OFFSET" || -z "$TEXT_VM_ADDRESS" || \
        -z "$EXTENSION_MAIN_STUB" ]]; then
    echo "Widget entry-point metadata is incomplete for $WIDGET_ARCH" >&2
    exit 1
  fi

  EXPECTED_OFFSET=$(( EXTENSION_MAIN_STUB - TEXT_VM_ADDRESS ))
  if (( ENTRY_OFFSET != EXPECTED_OFFSET )); then
    echo "Widget $WIDGET_ARCH entry point is not NSExtensionMain" >&2
    exit 1
  fi
done

echo "Widget extension entry point is valid: ${WIDGET_ARCH_LIST[*]}"
