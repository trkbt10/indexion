/**
 * @file Local relaxation around a dragged node.
 *
 * The global layout is deterministic (treemap pack). Dragging should
 * not trigger a full re-solve — we only apply a tiny one-step nudge
 * to its immediate (1-hop) neighbours so connecting edges don't
 * stretch absurdly long. Two forces are applied:
 *
 *   1. Spring pull: a neighbour beyond REST_LENGTH gets nudged
 *      toward the dragged node so the edge stops stretching.
 *   2. Mutual repulsion: neighbours that overlap each other get
 *      pushed apart so they don't all pile on top of the dragged
 *      node — the failure mode the previous pull-only design
 *      produced (every drag-frame collapsed neighbours toward the
 *      cursor, with nothing keeping them disjoint).
 *
 * Each frame's per-neighbour displacement is capped (MAX_STEP) so
 * many drag events in quick succession can't accumulate into a
 * runaway flow. The dragged node itself is never moved here — the
 * drag handler positions it directly.
 */

import type { ViewEdge, ViewGraph, ViewNode } from "../types.ts";

/** Spring rest length: edges shorter than this are not pulled in. */
const REST_LENGTH = 80;
/** Spring pull strength per frame (fraction of overshoot). Low so
 *  many drag events don't visibly slingshot the neighbour. */
const PULL_STRENGTH = 0.18;
/** Below this distance, two neighbours repel each other. Slightly
 *  larger than REST_LENGTH so the equilibrium has room. */
const REPEL_DISTANCE = 60;
/** Repulsion strength: how much of the overlap is corrected per
 *  frame. Symmetric, so both endpoints share the displacement. */
const REPEL_STRENGTH = 0.35;
/** Per-frame displacement cap (world units). Caps both pull and
 *  repel so a long drag can't fling a neighbour off-screen. */
const MAX_STEP = 18;

export function relaxNeighbours(graph: ViewGraph, node: ViewNode): void {
  const neighbours = collectNeighbours(graph, node);
  if (neighbours.length === 0) {
    return;
  }
  // Pass 1 — spring pull toward the dragged node, accumulated as
  // displacement deltas so we can clamp them before applying.
  const dxBuf = new Float64Array(neighbours.length);
  const dyBuf = new Float64Array(neighbours.length);
  const dzBuf = new Float64Array(neighbours.length);
  for (let i = 0; i < neighbours.length; i++) {
    const other = neighbours[i]!;
    if (other.pinned) {
      continue;
    }
    const dx = node.x - other.x;
    const dy = node.y - other.y;
    const dz = node.z - other.z;
    const dist = Math.hypot(dx, dy, dz);
    if (dist < REST_LENGTH || dist === 0) {
      continue;
    }
    const pull = (PULL_STRENGTH * (dist - REST_LENGTH)) / dist;
    dxBuf[i] += dx * pull;
    dyBuf[i] += dy * pull;
    dzBuf[i] += dz * pull;
  }

  // Pass 2 — mutual repulsion between neighbour pairs that are too
  // close. Without this, the spring pull collapses every neighbour
  // onto the dragged node's location.
  for (let i = 0; i < neighbours.length; i++) {
    const a = neighbours[i]!;
    if (a.pinned) {
      continue;
    }
    for (let j = i + 1; j < neighbours.length; j++) {
      const b = neighbours[j]!;
      if (b.pinned) {
        continue;
      }
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const dz = a.z - b.z;
      const dist = Math.hypot(dx, dy, dz);
      if (dist >= REPEL_DISTANCE || dist === 0) {
        continue;
      }
      const overlap = REPEL_DISTANCE - dist;
      const push = (REPEL_STRENGTH * overlap) / (2 * dist);
      // Each side takes half the correction.
      dxBuf[i] += dx * push;
      dyBuf[i] += dy * push;
      dzBuf[i] += dz * push;
      dxBuf[j] -= dx * push;
      dyBuf[j] -= dy * push;
      dzBuf[j] -= dz * push;
    }
  }

  // Apply with a per-neighbour step cap so cumulative drag events
  // can't accumulate into a runaway slide.
  for (let i = 0; i < neighbours.length; i++) {
    const other = neighbours[i]!;
    if (other.pinned) {
      continue;
    }
    const dx = clampStep(dxBuf[i]!);
    const dy = clampStep(dyBuf[i]!);
    const dz = clampStep(dzBuf[i]!);
    other.x += dx;
    other.y += dy;
    other.z += dz;
  }
}

function clampStep(v: number): number {
  if (v > MAX_STEP) return MAX_STEP;
  if (v < -MAX_STEP) return -MAX_STEP;
  return v;
}

/** Collect 1-hop neighbours of `node`. Walks the edge list once and
 *  deduplicates so a node connected to the dragged one by multiple
 *  edges only appears once in the relaxation. */
function collectNeighbours(graph: ViewGraph, node: ViewNode): ViewNode[] {
  const seen = new Set<string>();
  const out: ViewNode[] = [];
  for (const edge of graph.edges) {
    const other = neighbourIn(edge, node);
    if (!other || seen.has(other.id)) {
      continue;
    }
    seen.add(other.id);
    out.push(other);
  }
  return out;
}

function neighbourIn(edge: ViewEdge, node: ViewNode): ViewNode | null {
  if (edge.source === node) {
    return edge.target;
  }
  if (edge.target === node) {
    return edge.source;
  }
  return null;
}
