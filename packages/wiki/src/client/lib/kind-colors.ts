/**
 * @file Dynamic kind-based color assignment.
 *
 * Assigns colors to symbol kinds from a fixed palette, but does NOT
 * hardcode which kind gets which color. Colors are assigned in
 * encounter order and cached for consistency within a session.
 */

const PALETTE_BADGE = [
  "bg-blue-500/10 text-blue-400 border-blue-500/20",
  "bg-green-500/10 text-green-400 border-green-500/20",
  "bg-yellow-500/10 text-yellow-400 border-yellow-500/20",
  "bg-purple-500/10 text-purple-400 border-purple-500/20",
  "bg-red-500/10 text-red-400 border-red-500/20",
  "bg-cyan-500/10 text-cyan-400 border-cyan-500/20",
  "bg-orange-500/10 text-orange-400 border-orange-500/20",
  "bg-pink-500/10 text-pink-400 border-pink-500/20",
];

const PALETTE_TEXT = [
  "text-blue-400",
  "text-green-400",
  "text-yellow-400",
  "text-purple-400",
  "text-red-400",
  "text-cyan-400",
  "text-orange-400",
  "text-pink-400",
];

const PALETTE_HEX = [
  "#58a6ff",
  "#3fb950",
  "#d29922",
  "#bc8cff",
  "#f85149",
  "#79c0ff",
  "#e3b341",
  "#56d364",
];

const assignments = new Map<string, number>();

const indexOf = (kind: string): number => {
  const key = kind.toLowerCase();
  const existing = assignments.get(key);
  if (existing != null) {
    return existing;
  }
  const idx = assignments.size;
  assignments.set(key, idx);
  return idx;
};

/** Tailwind classes for badge styling. */
export const kindBadgeClass = (kind: string): string =>
  PALETTE_BADGE[indexOf(kind) % PALETTE_BADGE.length];

/** Tailwind text color class. */
export const kindTextClass = (kind: string): string =>
  PALETTE_TEXT[indexOf(kind) % PALETTE_TEXT.length];

/** Hex color string (for canvas/SVG). */
export const kindHex = (kind: string): string =>
  PALETTE_HEX[indexOf(kind) % PALETTE_HEX.length];
