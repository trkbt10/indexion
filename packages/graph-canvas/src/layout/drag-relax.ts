/**
 * @file Local relaxation around a dragged node.
 *
 * The global layout is deterministic (HDE). Dragging should not trigger
 * a full re-solve — we only apply a tiny 1-step nudge to the dragged
 * node's immediate neighbours so edges don't stretch awkwardly. This
 * runs instantly and has no ongoing cost.
 */

import type { ViewEdge, ViewGraph, ViewNode } from "../types.ts";

const PULL_STRENGTH = 0.25;
const REST_LENGTH = 80;

export function relaxNeighbours(graph: ViewGraph, node: ViewNode): void {
  for (const edge of graph.edges) {
    const other = neighbourIn(edge, node);
    if (!other || other.pinned) {
      continue;
    }
    const dx = node.x - other.x;
    const dy = node.y - other.y;
    const dz = node.z - other.z;
    const dist = Math.hypot(dx, dy, dz) || 1;
    if (dist < REST_LENGTH) {
      continue;
    }
    const pull = (PULL_STRENGTH * (dist - REST_LENGTH)) / dist;
    other.x += dx * pull;
    other.y += dy * pull;
    other.z += dz * pull;
  }
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
