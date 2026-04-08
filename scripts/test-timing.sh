#!/bin/sh
# Measure test execution time per package.
# Usage: ./scripts/test-timing.sh [--slow=N]
#   --slow=N  Only show packages taking >= N seconds (default: show all)
#
# Output: sorted by elapsed time (descending), one line per package.

set -e

SLOW_THRESHOLD=0

for arg in "$@"; do
  case "$arg" in
    --slow=*) SLOW_THRESHOLD="${arg#--slow=}" ;;
  esac
done

PACKAGES=$(moon test --target native --outline 2>/dev/null \
  | awk '{print $2}' | sort -u)

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

TOTAL_ELAPSED=0
TOTAL_TESTS=0
TOTAL_FAILED=0

for pkg in $PACKAGES; do
  START=$(date +%s)
  OUTPUT=$(moon test --target native -p "$pkg" 2>&1) || true
  END=$(date +%s)

  ELAPSED=$(( END - START ))
  TOTAL_ELAPSED=$(( TOTAL_ELAPSED + ELAPSED ))

  TESTS=$(echo "$OUTPUT" | grep -o 'Total tests: [0-9]*' | grep -o '[0-9]*' || echo "0")
  FAILED=$(echo "$OUTPUT" | grep -o 'failed: [0-9]*' | grep -o '[0-9]*' || echo "0")

  TOTAL_TESTS=$(( TOTAL_TESTS + TESTS ))
  TOTAL_FAILED=$(( TOTAL_FAILED + FAILED ))

  if [ "$ELAPSED" -ge "$SLOW_THRESHOLD" ]; then
    printf '%4ds  %3d tests  %s\n' "$ELAPSED" "$TESTS" "$pkg" >> "$TMPFILE"
  fi
done

echo "=== Test Timing Report ==="
echo ""
sort -rn "$TMPFILE"
echo ""
echo "---"
printf 'Total: %ds, %d tests, %d failed\n' "$TOTAL_ELAPSED" "$TOTAL_TESTS" "$TOTAL_FAILED"
