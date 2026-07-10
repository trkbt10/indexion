#!/bin/sh
# Sync version from moon.mod (SoT) to all version references.
# Run this before building to ensure version consistency.
#
# Targets:
#   - src/update/version.mbt (binary version constant)
#   - skills/.claude-plugin/marketplace.json (skills plugin version)
#   - skills/.claude-plugin/plugin.json (skills plugin manifest version)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MOD_FILE="$ROOT/moon.mod"
VERSION_MBT="$ROOT/src/update/version.mbt"
MARKETPLACE_JSON="$ROOT/skills/.claude-plugin/marketplace.json"
PLUGIN_JSON="$ROOT/skills/.claude-plugin/plugin.json"

# Extract version from moon.mod (SoT). The manifest is TOML, so the version
# line reads: version = "x.y.z"
VERSION=$(grep -E '^[[:space:]]*version[[:space:]]*=' "$MOD_FILE" | head -1 | sed 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$VERSION" ]; then
  echo "Error: Could not extract version from $MOD_FILE" >&2
  exit 1
fi

CHANGED=0

# --- Sync version.mbt ---
CURRENT_MBT=$(grep 'current_version' "$VERSION_MBT" | sed 's/.*"\([^"]*\)".*/\1/')
if [ "$VERSION" != "$CURRENT_MBT" ]; then
  echo "version.mbt: $CURRENT_MBT -> $VERSION"
  sed -i.bak "s/pub let current_version : String = \".*\"/pub let current_version : String = \"$VERSION\"/" "$VERSION_MBT"
  rm -f "$VERSION_MBT.bak"
  CHANGED=1
fi

# --- Sync marketplace.json ---
if [ -f "$MARKETPLACE_JSON" ]; then
  # Replace all "version": "x.y.z" occurrences
  CURRENT_MKT=$(grep '"version"' "$MARKETPLACE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ "$VERSION" != "$CURRENT_MKT" ]; then
    echo "marketplace.json: $CURRENT_MKT -> $VERSION"
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/g" "$MARKETPLACE_JSON"
    rm -f "$MARKETPLACE_JSON.bak"
    CHANGED=1
  fi
fi

# --- Sync plugin.json ---
if [ -f "$PLUGIN_JSON" ]; then
  CURRENT_PLG=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ "$VERSION" != "$CURRENT_PLG" ]; then
    echo "plugin.json: $CURRENT_PLG -> $VERSION"
    sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/g" "$PLUGIN_JSON"
    rm -f "$PLUGIN_JSON.bak"
    CHANGED=1
  fi
fi

if [ "$CHANGED" -eq 0 ]; then
  exit 0
fi
