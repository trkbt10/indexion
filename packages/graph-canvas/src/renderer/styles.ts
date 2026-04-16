/**
 * @file Theme presets and visual style configuration.
 *
 * Provides dark and light themes with per-kind node colors, edge styles,
 * and default node radii.
 */

import type { EdgeStyle, NodeStyle, ThemeColors } from "../types.ts";

const DEFAULT_NODE_STYLE: NodeStyle = { radius: 5, color: "#6b7280" };
const DEFAULT_EDGE_STYLE: EdgeStyle = { color: "#6b7280", dash: [], arrow: true };

export const DARK_THEME: ThemeColors = {
  background: "#0f0f14",
  labelColor: "#d1d5db",
  selectionColor: "#3b82f6",
  highlightColor: "#facc15",
  dimmedOpacity: 0.15,
  nodeStyles: {
    module: { radius: 8, color: "#7c3aed" },
    function: { radius: 5, color: "#06b6d4" },
    type: { radius: 6, color: "#f59e0b" },
    struct: { radius: 6, color: "#f59e0b" },
    variable: { radius: 4, color: "#10b981" },
    external: { radius: 6, color: "#6b7280" },
    internal: { radius: 7, color: "#8b5cf6" },
  },
  edgeStyles: {
    dependency: { color: "#4b5563", dash: [], arrow: true },
    circular: { color: "#ef4444", dash: [], arrow: true },
    calls: { color: "#06b6d4", dash: [4, 4], arrow: true },
    extends: { color: "#f59e0b", dash: [8, 4], arrow: true },
    implements: { color: "#8b5cf6", dash: [2, 4], arrow: true },
    declares: { color: "#374151", dash: [], arrow: false },
    references: { color: "#374151", dash: [2, 2], arrow: true },
    imports: { color: "#4b5563", dash: [6, 3], arrow: true },
  },
};

export const LIGHT_THEME: ThemeColors = {
  background: "#fafafa",
  labelColor: "#1f2937",
  selectionColor: "#2563eb",
  highlightColor: "#ca8a04",
  dimmedOpacity: 0.12,
  nodeStyles: {
    module: { radius: 8, color: "#6d28d9" },
    function: { radius: 5, color: "#0891b2" },
    type: { radius: 6, color: "#d97706" },
    struct: { radius: 6, color: "#d97706" },
    variable: { radius: 4, color: "#059669" },
    external: { radius: 6, color: "#9ca3af" },
    internal: { radius: 7, color: "#7c3aed" },
  },
  edgeStyles: {
    dependency: { color: "#d1d5db", dash: [], arrow: true },
    circular: { color: "#ef4444", dash: [], arrow: true },
    calls: { color: "#0891b2", dash: [4, 4], arrow: true },
    extends: { color: "#d97706", dash: [8, 4], arrow: true },
    implements: { color: "#7c3aed", dash: [2, 4], arrow: true },
    declares: { color: "#e5e7eb", dash: [], arrow: false },
    references: { color: "#e5e7eb", dash: [2, 2], arrow: true },
    imports: { color: "#d1d5db", dash: [6, 3], arrow: true },
  },
};

export function getNodeStyle(kind: string, theme: ThemeColors): NodeStyle {
  return theme.nodeStyles[kind] ?? DEFAULT_NODE_STYLE;
}

export function getEdgeStyle(kind: string, theme: ThemeColors): EdgeStyle {
  return theme.edgeStyles[kind] ?? DEFAULT_EDGE_STYLE;
}

export function resolveTheme(pref: "dark" | "light" | "auto"): ThemeColors {
  if (pref === "dark") return DARK_THEME;
  if (pref === "light") return LIGHT_THEME;
  // "auto": respect system preference
  if (typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches) {
    return DARK_THEME;
  }
  return LIGHT_THEME;
}
