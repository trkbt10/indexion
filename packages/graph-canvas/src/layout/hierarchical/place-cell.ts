/**
 * @file Place leaf nodes inside a treemap cell rectangle.
 *
 * Uses a jittered grid in 2D so density is uniform across the cell
 * and no two nodes overlap. The grid cell size is derived from the
 * available area and the node count, then perturbed by ≤ 25% so the
 * result doesn't read as a regular lattice.
 *
 * Node z is set to 0 — the renderer projects (x, y, z) but for a
 * 2D-style hierarchy view we keep everything coplanar so the user sees
 * the actual treemap structure rather than a 3D-projected ambiguity.
 */

import type { Rect, ViewNode } from "../../types.ts";
import { writeNode } from "../geometry.ts";

export type CellPlacementArgs = {
  readonly nodes: readonly ViewNode[];
  readonly rect: Rect;
  /** Reserved padding inside the cell. Nodes are placed in the inner
   *  rect (rect inset by `padding`) so they don't touch the cell
   *  border or the shell ring. */
  readonly padding: number;
  /** Optional ordering — typically by adjacency so connected nodes
   *  end up near each other. Default order is `nodes`. */
  readonly ordered?: readonly ViewNode[];
};

/** Place every node inside the cell rectangle. If the cell is too
 *  small to host the count comfortably, nodes still get unique
 *  positions — they just sit closer together. Never returns NaN. */
export function placeCellNodes(args: CellPlacementArgs): void {
  const { nodes, rect, padding } = args;
  const ordered = args.ordered ?? nodes;
  const n = ordered.length;
  if (n === 0) {
    return;
  }
  const innerW = Math.max(1e-6, rect.w - 2 * padding);
  const innerH = Math.max(1e-6, rect.h - 2 * padding);
  const innerX = rect.x + padding;
  const innerY = rect.y + padding;
  if (n === 1) {
    writeNode(ordered[0]!, {
      x: innerX + innerW / 2,
      y: innerY + innerH / 2,
      z: 0,
    });
    return;
  }
  // Pick the grid (cols × rows) with aspect ratio closest to the
  // cell's aspect ratio. cols·rows ≥ n; we pick cols = ceil(sqrt(n·ar))
  // where ar = innerW / innerH so per-cell aspect ratio comes out near 1.
  const ar = innerW / innerH;
  const cols = Math.max(1, Math.ceil(Math.sqrt(n * ar)));
  const rows = Math.max(1, Math.ceil(n / cols));
  const cellW = innerW / cols;
  const cellH = innerH / rows;
  // Jitter ≤ 25% of the smaller cell dimension so the grid breaks up
  // visually but still guarantees disjointness.
  const jitter = Math.min(cellW, cellH) * 0.25;
  // Deterministic LCG so layout is stable across reruns.
  let state = (n * 2654435761) >>> 0;
  const rand = (): number => {
    state = (state * 1103515245 + 12345) >>> 0;
    return state / 0x100000000;
  };
  for (let i = 0; i < n; i++) {
    const c = i % cols;
    const r = Math.floor(i / cols);
    const cx = innerX + (c + 0.5) * cellW;
    const cy = innerY + (r + 0.5) * cellH;
    const jx = (rand() - 0.5) * 2 * jitter;
    const jy = (rand() - 0.5) * 2 * jitter;
    writeNode(ordered[i]!, { x: cx + jx, y: cy + jy, z: 0 });
  }
}
