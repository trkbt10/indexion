/**
 * @file Deterministic cluster colouring.
 *
 * Top-level cluster paths are mapped to a categorical palette so each
 * top-level group reads as its own visual region. Sub-clusters under
 * the same top inherit the parent's hue, allowing the user to track
 * "what belongs to what" by colour without having to read labels.
 *
 * The palette is muted — dark backgrounds + saturated colours produce
 * a cyber-disco aesthetic that fights the data. We pick low-chroma,
 * mid-luminance colours so the fill reads as "tinted background"
 * rather than "category badge".
 *
 * Lookup is determined by the *top-level* path, hashed into the
 * palette. Adding/removing clusters does not reshuffle existing
 * colours unless the *set* of top-level paths changes. The hash is
 * deterministic across runs.
 */

import { Color } from "three";

/** Muted palette: 12 hues with similar luminance so no single
 *  category screams. Chosen to remain distinguishable on a near-
 *  black background. RGB values were picked by hand from a Catppuccin
 *  Mocha–adjacent set, then desaturated by ~30%.
 *
 *  Test the change visually before tweaking — values that look fine
 *  on a bright monitor may bleed into the bg on a dim one. */
const PALETTE: readonly string[] = [
  "#7aa2c8", // soft blue
  "#a3be8c", // sage green
  "#d4a373", // muted amber
  "#b48ead", // dusty mauve
  "#88c0d0", // pale teal
  "#bf616a", // muted red
  "#a3a3c2", // lavender grey
  "#8fbcbb", // moss teal
  "#ebcb8b", // sand
  "#c4929d", // rose
  "#81a1c1", // steel blue
  "#9d8ec3", // periwinkle
];

const PALETTE_COLORS: readonly Color[] = PALETTE.map((hex) => new Color(hex));

/** Top-level path → palette index. Memoised so repeated lookups for
 *  the same path are O(1) and so the assignment is stable across the
 *  layer's lifetime. */
const assignmentCache = new Map<string, number>();

/** Return a Color for the cluster's *top-level* path. Sub-cluster
 *  paths share the colour of their root, so a single click on
 *  "src/foo/bar" reads as the same colour as "src". */
export function clusterColor(path: string): Color {
  const top = topLevelOf(path);
  let idx = assignmentCache.get(top);
  if (idx === undefined) {
    idx = hashString(top) % PALETTE_COLORS.length;
    assignmentCache.set(top, idx);
  }
  return PALETTE_COLORS[idx]!;
}

/** Top-level segment of a slash-separated cluster path. Used to
 *  group sub-clusters under the same hue. */
export function topLevelOf(path: string): string {
  const slash = path.indexOf("/");
  return slash < 0 ? path : path.slice(0, slash);
}

/** djb2 — a simple, well-distributed string hash. Stable across
 *  platforms; no Math.random. */
function hashString(s: string): number {
  let h = 5381 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
  }
  return h;
}
