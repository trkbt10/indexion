/**
 * @file Theme presets and visual style configuration.
 *
 * Monochrome palette inspired by Linear / Vercel: neutral grayscale for
 * structure, a single cool accent for selection, and subtle warm accent
 * for highlights. Kinds differentiate via luminance and radius rather
 * than hue, keeping the graph visually quiet.
 */

import type { EdgeStyle, NodeStyle, ThemeColors } from "../types.ts";

const DEFAULT_NODE_STYLE: NodeStyle = { radius: 5, color: "#71717a" };
const DEFAULT_EDGE_STYLE: EdgeStyle = {
  color: "#3f3f46",
  dash: [],
  arrow: true,
};

export const DARK_THEME: ThemeColors = {
  background: "#09090b",
  labelColor: "#a1a1aa",
  selectionColor: "#fafafa",
  highlightColor: "#fafafa",
  tooltipBackground: "rgba(24, 24, 27, 0.96)",
  tooltipBorder: "#3f3f46",
  dimmedOpacity: 0.35,
  nodeStyles: {
    // Narrower luminance range so the hub / leaf contrast is subtle.
    module: { radius: 6.5, color: "#e4e4e7" },
    function: { radius: 4, color: "#a1a1aa" },
    type: { radius: 5, color: "#c4c4c9" },
    struct: { radius: 5, color: "#c4c4c9" },
    variable: { radius: 3.5, color: "#8b8b92" },
    external: { radius: 5, color: "#71717a" },
    internal: { radius: 5.5, color: "#d1d1d6" },
  },
  edgeStyles: {
    dependency: { color: "#4b4b52", dash: [], arrow: true },
    circular: { color: "#8b8b92", dash: [], arrow: true },
    calls: { color: "#60606a", dash: [3, 3], arrow: true },
    extends: { color: "#60606a", dash: [6, 3], arrow: true },
    implements: { color: "#60606a", dash: [2, 3], arrow: true },
    declares: { color: "#3a3a40", dash: [], arrow: false },
    references: { color: "#3a3a40", dash: [2, 2], arrow: true },
    imports: { color: "#4b4b52", dash: [5, 3], arrow: true },
  },
};

export const LIGHT_THEME: ThemeColors = {
  background: "#ffffff",
  labelColor: "#52525b",
  selectionColor: "#09090b",
  highlightColor: "#09090b",
  tooltipBackground: "rgba(255, 255, 255, 0.96)",
  tooltipBorder: "#e4e4e7",
  dimmedOpacity: 0.15,
  nodeStyles: {
    module: { radius: 7, color: "#09090b" },
    function: { radius: 4, color: "#52525b" },
    type: { radius: 5, color: "#27272a" },
    struct: { radius: 5, color: "#27272a" },
    variable: { radius: 3, color: "#71717a" },
    external: { radius: 5, color: "#a1a1aa" },
    internal: { radius: 6, color: "#18181b" },
  },
  edgeStyles: {
    dependency: { color: "#d4d4d8", dash: [], arrow: true },
    circular: { color: "#71717a", dash: [], arrow: true },
    calls: { color: "#a1a1aa", dash: [3, 3], arrow: true },
    extends: { color: "#a1a1aa", dash: [6, 3], arrow: true },
    implements: { color: "#a1a1aa", dash: [2, 3], arrow: true },
    declares: { color: "#e4e4e7", dash: [], arrow: false },
    references: { color: "#e4e4e7", dash: [2, 2], arrow: true },
    imports: { color: "#d4d4d8", dash: [5, 3], arrow: true },
  },
};

export function getNodeStyle(kind: string, theme: ThemeColors): NodeStyle {
  return theme.nodeStyles[kind] ?? DEFAULT_NODE_STYLE;
}

export function getEdgeStyle(kind: string, theme: ThemeColors): EdgeStyle {
  return theme.edgeStyles[kind] ?? DEFAULT_EDGE_STYLE;
}

export function resolveTheme(pref: "dark" | "light" | "auto"): ThemeColors {
  if (pref === "dark") {
    return DARK_THEME;
  }
  if (pref === "light") {
    return LIGHT_THEME;
  }
  if (
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  ) {
    return DARK_THEME;
  }
  return LIGHT_THEME;
}
